# Kotlin Flow to FlowKit Migration Guide

A complete mapping from Kotlin Flow APIs to their FlowKit equivalents, with side-by-side code comparisons for the most common patterns.

## Overview

FlowKit is designed so Kotlin Flow knowledge transfers directly. The mental model is identical: cold flows, hot `StateFlow`/`SharedFlow`, the same operator names, the same sharing strategies. This guide covers every API surface with its Swift equivalent and highlights the places where Swift idioms differ from Kotlin's.

## Builders

| Kotlin | FlowKit | Notes |
|--------|---------|-------|
| `flow { emit(x) }` | `Flow { await $0.emit(x) }` | Body closure receives a `Collector` |
| `flowOf(1, 2, 3)` | `Flow(of: 1, 2, 3)` | Variadic initializer |
| `listOf(1,2,3).asFlow()` | `[1, 2, 3].asFlow()` | `Sequence.asFlow()` extension |
| `emptyFlow()` | `Flow<T>.empty` | Static property |
| `flow { }` (never completes) | `Flow<T>.never` | Suspends until cancelled |
| `ThrowingFlow { try await ... }` | N/A in Kotlin (uses `catch`) | Explicit throwing variant |

## Transform and filter

| Kotlin | FlowKit | Notes |
|--------|---------|-------|
| `.map { }` | `.map { }` | Both support `async` transform closures |
| `.mapNotNull { }` | `.compactMap { }` | Swift naming convention |
| `.filter { }` | `.filter { }` | Identical |
| `.transform { emit() }` | `.transform { value, collector in }` | Collector passed explicitly |
| `.take(n)` | `.prefix(n)` | Swift `Sequence`-aligned name |
| `.drop(n)` | `.dropFirst(n)` | Swift `Sequence`-aligned name |
| `.scan(initial) { acc, v -> }` | `.scan(initial) { acc, v in }` | Identical semantics |

## Combining

| Kotlin | FlowKit | Notes |
|--------|---------|-------|
| `.zip(other)` | `.zip(other)` | Positional pairing; completes when either ends |
| `.combineLatest(other) { a, b -> }` | `.combineLatest(other) { a, b in }` | Waits for both to emit at least once |
| `merge(a, b, c)` | `Flow.merge(a, b, c)` | Static method on `Flow` |

## Flattening

| Kotlin | FlowKit | Notes |
|--------|---------|-------|
| `.flatMapConcat { }` | `.flatMap { }` | Sequential; waits for each inner flow |
| `.flatMapMerge(concurrency = n) { }` | `.flatMap(maxConcurrent: n) { }` | Concurrent with limit |
| `.flatMapLatest { }` | `.flatMapLatest { }` | Cancels previous inner flow on new upstream value |

## Rate limiting

| Kotlin | FlowKit | Notes |
|--------|---------|-------|
| `.debounce(300)` | `.debounce(for: .milliseconds(300))` | Uses `Duration`; clock-injectable for testing |
| `.throttleLatest(100)` | `.throttle(for: .milliseconds(100), latest: true)` | Emits latest in window |
| `.throttleFirst(100)` | `.throttle(for: .milliseconds(100), latest: false)` | Emits first in window |
| `.distinctUntilChanged()` | `.removeDuplicates()` | Requires `Equatable` |
| `.distinctUntilChangedBy { }` | `.removeDuplicates(by:)` | Custom predicate variant |
| `.sample(1000)` | `.sample(every: .seconds(1))` | Periodic sampling |

## Buffering

| Kotlin | FlowKit | Notes |
|--------|---------|-------|
| `.buffer(capacity, DROP_OLDEST)` | `.buffer(size: n, policy: .dropOldest)` | Drops oldest when full |
| `.buffer(capacity, DROP_LATEST)` | `.buffer(size: n, policy: .dropLatest)` | Drops incoming when full |
| `.buffer(capacity, SUSPEND)` | `.buffer(size: n, policy: .suspend)` | True backpressure via actor |
| `.conflate()` | `.keepingLatest()` | Sugar for `buffer(size: 1, policy: .dropOldest)` |

## Error handling

| Kotlin | FlowKit | Notes |
|--------|---------|-------|
| `.catch { e -> emit(fallback) }` | `.catch { error, collector in await collector.emit(fallback) }` | Converts `ThrowingFlow` → `Flow` |
| `.retry(3)` | `.retry(3)` | Re-executes body up to N times |
| `.retry { e, attempt -> }` | `.retryWhen { error, attempt in }` | Conditional retry with async predicate |
| `.onErrorReturn(value)` | `.catch { _, c in await c.emit(value) }` | Inline in `catch` |

## Lifecycle operators

| Kotlin | FlowKit | Notes |
|--------|---------|-------|
| `.onStart { emit() }` | `.onStart { }` | Runs before upstream starts |
| `.onEach { }` | `.onEach { }` | Side effects without transforming |
| `.onCompletion { e -> }` | `.onCompletion { error in }` | `error` is `nil` on normal completion |

## Terminal operators

| Kotlin | FlowKit | Notes |
|--------|---------|-------|
| `.collect { }` | `.collect { }` | Primary terminal; suspends until complete |
| `.collectLatest { }` | `.collectLatest { }` | Cancels previous action on new value |
| `.first()` | `.first()` | Returns optional; `nil` if flow is empty |
| `.firstOrNull { }` | `.first(where:)` | Predicate variant |
| `.any { }` / `.all { }` | `.contains(where:)` / `.allSatisfy(_:)` | Return `Bool` |
| `.single()` | `.exactlyOne()` | Throws if zero or multiple values |
| `.toList()` | `.toArray()` | Collects all values |
| `.fold(initial) { acc, v -> }` | `.reduce(initial) { acc, v in }` | Left fold |
| `.launchIn(scope)` | `.launch(in: scope)` | Fire-and-forget; returns `Task` handle |

Since 2.4.2, `first()`, `first(where:)`, `contains(where:)`, `allSatisfy(_:)`, `prefix(_:)` and `prefix(while:)` cancel the upstream as soon as they have their answer. They return even when the upstream stays open, for example a `callbackFlow` that waits in `awaitClose`. A flow that never emits and never completes still keeps `first()` suspended, so wrap the call in a timeout when the source can stay silent.

## Hot streams

| Kotlin | FlowKit | Notes |
|--------|---------|-------|
| `MutableStateFlow(initial)` | `MutableStateFlow(initial)` | Identical name and semantics |
| `MutableSharedFlow(replay = n)` | `MutableSharedFlow(replay: n)` | Identical |
| `stateIn(scope, started, initial)` | `.asStateFlow(initialValue:strategy:)` | No explicit scope; uses `FlowScope` separately |
| `shareIn(scope, started, replay)` | `.asSharedFlow(replay:strategy:)` | Same |
| `SharingStarted.Eagerly` | `.eager` | Starts immediately |
| `SharingStarted.Lazily` | `.lazy` | Starts on first subscriber, runs until scope ends |
| `SharingStarted.WhileSubscribed(5_000)` | `.whileSubscribed(stopTimeout: .seconds(5))` | Recommended default |

## UI collection

| Kotlin (Android) | FlowKit (iOS/macOS) |
|------------------|---------------------|
| `collectAsStateWithLifecycle(initial)` | `@CollectedState(flow) var state: T = initial` |
| `LifecycleCoroutineScope.launchWhenStarted` | `UIViewController.flowScope` + `.launch(in:)` |
| `viewLifecycleOwner.lifecycleScope` | `UIViewController.flowScope` |
| `lifecycleScope.launchWhenResumed` | `UIViewController.viewWillAppear` + cancel on `viewWillDisappear` |

## Testing

| Kotlin (Turbine) | FlowKit (FlowReader) |
|------------------|----------------------|
| `flow.test { }` | `flow.probing { reader in }` |
| `awaitItem()` | `try await reader.awaitValue()` |
| `awaitComplete()` | `try await reader.expectCompletion()` |
| `awaitError()` | `try await reader.expectError(_:matching:)` |
| `expectNoEvents()` | `try await reader.expectNextValue(_:)` after a known emission |
| `TestCoroutineScheduler` / `runTest` | `TestClock` + `probing` |
| `advanceTimeBy(ms)` | `await clock.advance(by: .milliseconds(ms))` |

## Side-by-side comparisons

### Debounced search

**Kotlin:**
```kotlin
class SearchViewModel(private val repo: ProductRepository) : ViewModel() {
    private val query = MutableStateFlow("")

    val results: StateFlow<SearchState> = query
        .debounce(300)
        .distinctUntilChanged()
        .filter { it.isNotEmpty() }
        .flatMapLatest { q -> repo.search(q) }
        .map { SearchState.Loaded(it) }
        .catch { emit(SearchState.Error("Search failed")) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), SearchState.Idle)
}
```

**FlowKit:**
```swift
@Observable
@MainActor
final class SearchViewModel {
    private let repo: ProductRepository
    private let query = MutableStateFlow("")

    let results: any StateFlow<SearchState>

    init(repo: ProductRepository) {
        self.repo = repo
        results = query.asFlow()
            .debounce(for: .milliseconds(300))
            .removeDuplicates()
            .filter { !$0.isEmpty }
            .mapThrowing { $0 }  // Flow -> ThrowingFlow, so flatMapLatest can return a ThrowingFlow
            .flatMapLatest { q -> ThrowingFlow<[Product]> in repo.search(q) }
            .map { SearchState.loaded($0) }
            .catch { _, collector in await collector.emit(.error("Search failed")) }
            .asStateFlow(initialValue: .idle, strategy: .whileSubscribed(stopTimeout: .seconds(5)))
    }

    func update(query text: String) { query.value = text }
}
```

Key differences: `flatMapLatest` over a `ThrowingFlow` needs a `Flow` converted with `mapThrowing` first, and an explicit return type annotation in Swift 6; `catch` receives the collector explicitly rather than using `emit` via `this`; `stateIn` becomes `asStateFlow` with a separate `FlowScope`.

---

### Session state sharing

**Kotlin:**
```kotlin
class SessionManager(private val authService: AuthService) {
    private val _state = MutableStateFlow<SessionState>(SessionState.SignedOut)

    val sessionState: StateFlow<SessionState> = _state.asStateFlow()

    init {
        authService.events
            .onEach { event ->
                _state.value = when (event) {
                    is AuthEvent.SignedIn -> SessionState.SignedIn(event.user)
                    is AuthEvent.SignedOut -> SessionState.SignedOut
                    is AuthEvent.Error -> SessionState.Error(event.message)
                }
            }
            .launchIn(GlobalScope) // simplified for illustration
    }
}
```

**FlowKit:**
```swift
actor SessionManager {
    private let _state = MutableStateFlow<SessionState>(.signedOut)
    var sessionState: any StateFlow<SessionState> { _state }

    init(authService: AuthService) {
        Task {
            await authService.events.collect { event in
                switch event {
                case .signedIn(let user): _state.value = .signedIn(user)
                case .signedOut: _state.value = .signedOut
                case .error(let message): _state.value = .error(message)
                }
            }
        }
    }
}
```

Key differences: `actor` replaces `@HiltViewModel`/`class`; `_state.value = ` stays the same, because `MutableStateFlow` has a synchronous `value` setter; `launchIn` becomes `Task { }` or `launch(in: scope)` for proper cancellation.

---

### Form validation with combine

**Kotlin:**
```kotlin
val isFormValid: StateFlow<Boolean> = combine(username, password, email) { u, p, e ->
    u.length >= 3 && p.length >= 8 && e.contains('@')
}.stateIn(viewModelScope, SharingStarted.Eagerly, false)
```

**FlowKit:**
```swift
// combineLatest takes the other flows as arguments, for 2 to 6 flows in total:
let isFormValid: any StateFlow<Bool> = username
    .combineLatest(password, email) { u, p, e in
        u.count >= 3 && p.count >= 8 && e.contains("@")
    }
    .asStateFlow(initialValue: false, strategy: .eager)
```

Key difference: FlowKit has no free `combine` function. `combineLatest` is a method on the first flow, and it has overloads that take 1 to 5 more flows (2 to 6 flows in total). Each overload has a variant without a transform closure that emits a tuple, and a variant with a transform closure. For more than six flows, chain `combineLatest` calls.

## Conceptual differences

**No `CoroutineScope` parameter on operators.** In Kotlin, `stateIn` and `shareIn` take an explicit `CoroutineScope` to anchor the upstream collection. In FlowKit, `asStateFlow` and `asSharedFlow` use an internal `Task` and rely on the `SharingStrategy` to control upstream lifetime. Pass a `FlowScope` to `launch(in:)` when you need explicit scope control over the collection site.

**`flow { }` body receives a `Collector`, not `this`.** In Kotlin, `emit` is called directly in the `flow { }` block because the block is a `FlowCollector` receiver. In FlowKit, the body closure receives an explicit `Collector<Element>` parameter. Use `await collector.emit(value)` or the trailing-closure shorthand `$0`.

**Errors require `ThrowingFlow`.** Kotlin `Flow` can carry errors (the flow itself is always non-throwing; errors surface via `catch`). FlowKit uses separate `Flow` and `ThrowingFlow` types. The compiler enforces which is which at every call site.

**`MutableStateFlow.value` is settable.** As in Kotlin, `_state.value = newValue` is synchronous. `MutableStateFlow` is a `Sendable` class, not an actor, so no `await` is needed. `_state.send(newValue)` does the same thing. Only the read-only `StateFlow` view has no setter.

## Related concepts

- <doc:HotVsColdStreams>: cold/hot distinction and sharing strategies
- <doc:FlowVsThrowingFlow>: when to use each stream type
- <doc:CancellationSemantics>: Swift structured concurrency vs Kotlin coroutine cancellation
