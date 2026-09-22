# Flow vs ThrowingFlow

A decision guide for choosing between ``FlowCore/Flow`` and ``FlowCore/ThrowingFlow``, and how to convert between them when your pipeline crosses the boundary.

## Overview

FlowKit uses two distinct stream types rather than a single `Result`-emitting type. The distinction is load-bearing: the Swift compiler enforces it at call sites, operators are defined separately on each, and conversion between them is always explicit. This catches a whole class of bugs, such as silent error swallowing and incorrect error propagation, at compile time rather than runtime.

## The decision rule

Ask one question: **can this source ever fail with an error?**

| Source | Type | Reason |
|--------|------|--------|
| Keyboard input from a `UITextField` | `Flow<String>` | Text field observation cannot throw |
| GPS coordinates from `CLLocationManager` | `Flow<CLLocation>` | Sensor callbacks are non-throwing |
| Timer ticks | `Flow<Date>` | Timers cannot fail |
| App foreground/background state | `Flow<ScenePhase>` | Notification-based, always succeeds |
| Network search request | `ThrowingFlow<[Product]>` | HTTP can fail with `URLError` |
| Database query | `ThrowingFlow<[Article]>` | SQLite/CoreData can throw |
| File read | `ThrowingFlow<Data>` | File I/O can fail |
| Authenticated session state | Depends (see below) | Refresh can fail; base state cannot |

When in doubt, keep the boundary as close to the actual failure site as possible. A `Flow<String>` user-input stream should stay `Flow<String>` through debouncing and deduplication. Only the network call that consumes the query becomes a `ThrowingFlow`.

## Flow: non-failing streams

Use ``FlowCore/Flow`` for streams whose source cannot produce an error. The compiler enforces this: `Flow.collect` does not `throws`, so you cannot accidentally `try` out of it.

```swift
// User's search query. Typed text cannot fail.
let searchQuery: Flow<String> = MutableStateFlow("").asFlow()
    .debounce(for: .milliseconds(300))
    .removeDuplicates()
    .filter { !$0.isEmpty }

// Location updates. Sensor delivery cannot fail (permission errors
// are a separate concern, handled by the CLLocationManager delegate).
let locationUpdates: Flow<CLLocation> = Flow { collector in
    let delegate = LocationDelegate()
    locationManager.delegate = delegate
    locationManager.startUpdatingLocation()
    for await location in delegate.locations {
        await collector.emit(location)
    }
}

// Form field state. Derived from already-loaded data.
let isFormValid: Flow<Bool> = username.combineLatest(password) { user, pass in
    !user.isEmpty && pass.count >= 8
}
```

## ThrowingFlow: fallible streams

Use ``FlowCore/ThrowingFlow`` when the source can throw. The collector's `emit` is `throws`, so error propagation is explicit throughout the chain.

```swift
// Network search. Can fail with URLError, server errors, or decoding errors.
let searchResults: ThrowingFlow<[Product]> = ThrowingFlow { collector in
    let url = SearchEndpoint.url(for: query)
    let (data, response) = try await URLSession.shared.data(from: url)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        throw SearchError.serverError
    }
    let products = try JSONDecoder().decode([Product].self, from: data)
    try await collector.emit(products)
}

// Database query. Can fail if the database is unavailable or migrating.
let articles: ThrowingFlow<[Article]> = ThrowingFlow { collector in
    let cached = try await articleDatabase.fetchAll()
    try await collector.emit(cached)
    let fresh = try await articleAPI.fetchLatest()
    try await articleDatabase.upsert(fresh)
    try await collector.emit(fresh)
}
```

## Converting between the two

### ThrowingFlow → Flow: catch errors at the boundary

Use `catch` to handle errors and return a non-failing `Flow`. This is the most common conversion and keeps error handling close to the failure site:

```swift
// The search UI should show an error state, never crash.
// Convert ThrowingFlow<[Product]> → Flow<SearchState> at the ViewModel layer.
let state: Flow<SearchState> = searchResults
    .map { SearchState.loaded($0) }
    .catch { error, collector in
        // Emit a fallback state. The flow becomes non-throwing.
        await collector.emit(.error("Search unavailable. Check your connection."))
    }
```

A more sophisticated fallback emits cached data before the error state:

```swift
let articlesState: Flow<ArticleListState> = articleAPI.fetchLatest()
    .map { ArticleListState.loaded($0) }
    .catch { _, collector in
        if let cached = try? await articleDatabase.fetchAll(), !cached.isEmpty {
            await collector.emit(.loaded(cached))
        } else {
            await collector.emit(.empty)
        }
    }
```

### ThrowingFlow → Flow: let errors propagate, handle at collection site

If you want to handle errors at the collection call site rather than inline, collect the `ThrowingFlow` directly with `try`:

```swift
do {
    try await productRepository.search(query).collect { products in
        display(products)
    }
} catch {
    showError(error)
}
```

### Flow → ThrowingFlow: add potential failure

When a non-failing operation precedes a potentially-failing one, `flatMapLatest` naturally bridges them because the transform closure returns a `ThrowingFlow`:

```swift
// searchQuery is Flow<String>. Text field, cannot fail.
// productRepository.search returns ThrowingFlow<[Product]>. Network, can fail.
let results: ThrowingFlow<[Product]> = searchQuery
    .flatMapLatest { query -> ThrowingFlow<[Product]> in
        query.isEmpty ? .empty : productRepository.search(query)
    }
```

The `flatMapLatest` overload on `Flow` that returns a `ThrowingFlow` produces a `ThrowingFlow<U>`, and the type system tracks the boundary automatically.

## Pair example: form validation and submission

This illustrates the full lifecycle: non-failing form state, converting to throwing at the submission boundary, and recovering back to non-failing for the UI:

```swift
// Form fields. Cannot fail, stay as Flow<String>.
let username: Flow<String> = usernameField.asFlow()
let password: Flow<String> = passwordField.asFlow()

// Validation state. Derived, cannot fail.
let isValid: Flow<Bool> = username.combineLatest(password) { u, p in
    u.count >= 3 && p.count >= 8
}

// On submit: crossing into ThrowingFlow at the network boundary.
func submit(username: String, password: String) -> ThrowingFlow<AuthSession> {
    ThrowingFlow { collector in
        let session = try await authService.login(username: username, password: password)
        try await collector.emit(session)
    }
}

// ViewModel wires it all together, recovering to non-failing for the UI.
let authState: any StateFlow<AuthState> = submitTap
    .flatMapLatest { _ -> ThrowingFlow<AuthState> in
        submit(username: currentUsername, password: currentPassword)
            .map { AuthState.signedIn($0) }
    }
    .catch { _, collector in
        await collector.emit(.error("Login failed. Check your credentials."))
    }
    .asStateFlow(initialValue: .signedOut)
```

## Related concepts

- <doc:HotVsColdStreams>: when to convert a `Flow` to a hot `StateFlow` or `SharedFlow`
- <doc:CancellationSemantics>: how cancellation propagates through both stream types
