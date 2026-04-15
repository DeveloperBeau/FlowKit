# FlowKit

[![Swift 6.3](https://img.shields.io/badge/Swift-6.3-orange.svg)](https://swift.org)
[![Xcode 26.4](https://img.shields.io/badge/Xcode-26.4+-blue.svg)](https://developer.apple.com/xcode/)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2016%2B%20%7C%20macOS%2013%2B%20%7C%20tvOS%2016%2B%20%7C%20watchOS%209%2B%20%7C%20visionOS%201%2B-brightgreen.svg)](https://swift.org/platform-support/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/Docs-DocC-blue.svg)](https://developerbeau.github.io/FlowKit/documentation/flow/)

**Kotlin Flow semantics in Swift, with Swift-idiomatic API.**

Full API documentation: <https://developerbeau.github.io/FlowKit/documentation/flow/>

FlowKit brings the Kotlin Flow mental model to Swift: cold asynchronous streams (`Flow`, `ThrowingFlow`), hot multicast primitives (`StateFlow`, `SharedFlow`), a rich operator library, and built-in testing infrastructure with virtual time.

## Toolchain requirements

| Requirement | Version |
|---|---|
| Swift | **6.3+** |
| Xcode | **26.4+** (Swift 6.3 ships with Xcode 26.4) |
| Xcode 17–26.3 | Requires manually installed Swift 6.3 toolchain from [swift.org/install](https://www.swift.org/install/) |
| iOS | 16.0+ |
| macOS | 13.0+ |
| tvOS | 16.0+ |
| watchOS | 9.0+ |
| visionOS | 1.0+ |

> **Note on older Xcode:** FlowKit uses Swift 6.2 and 6.3 language features (`@concurrent`, `@specialize`, isolated deinit, `Observations` async sequence). If you're on Xcode 17–26.3, install the Swift 6.3 toolchain from [swift.org/install](https://www.swift.org/install/) and select it in Xcode's **Toolchains** menu.

## Installation

Add FlowKit to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/YOUR_ORG/FlowKit", from: "0.1.0")
]
```

Then add `Flow` to production targets and `FlowTesting` to test targets:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "Flow", package: "FlowKit")
    ]
),
.testTarget(
    name: "MyAppTests",
    dependencies: [
        "MyApp",
        .product(name: "FlowTesting", package: "FlowKit")
    ]
)
```

## Four motivating examples

### 1. Offline-first article feed

```swift
let articles: ThrowingFlow<[Article]> = ThrowingFlow { collector in
    // Emit cached articles first so the UI has something to show
    let cached = try await articleDatabase.fetchAll()
    try await collector.emit(cached)

    // Then fetch fresh articles from the network
    let fresh = try await articleAPI.fetchLatest()
    try await articleDatabase.upsert(fresh)
    try await collector.emit(fresh)
}

try await articles
    .map { articles in articles.filter { !$0.isArchived } }
    .collect { visibleArticles in
        articleListView.display(visibleArticles)
    }
```

### 2. Shared user session state (`MutableStateFlow`)

```swift
enum SessionState: Sendable, Equatable {
    case signedOut
    case signingIn
    case signedIn(User)
    case error(String)
}

@MainActor
final class SessionManager {
    private let state = MutableStateFlow<SessionState>(.signedOut)
    var sessionState: any StateFlow<SessionState> { state }

    func signIn(email: String, password: String) async {
        await state.send(.signingIn)
        do {
            let user = try await authAPI.signIn(email: email, password: password)
            await state.send(.signedIn(user))
        } catch {
            await state.send(.error(error.localizedDescription))
        }
    }
}

// Multiple screens observe the same session state:
for await state in sessionManager.sessionState.asFlow() {
    switch state {
    case .signedIn(let user): updateProfile(user)
    case .signedOut: navigateToSignIn()
    case .signingIn: showLoadingIndicator()
    case .error(let message): showError(message)
    }
}
```

### 3. One-shot navigation events (`MutableSharedFlow`)

```swift
enum NavigationEvent: Sendable {
    case presentAlert(title: String, message: String)
    case navigateToDetail(productID: String)
    case dismissCurrentScreen
}

@MainActor
final class NavigationCoordinator {
    private let events = MutableSharedFlow<NavigationEvent>(replay: 0)
    var eventStream: any SharedFlow<NavigationEvent> { events }

    func present(alert title: String, message: String) async {
        await events.emit(.presentAlert(title: title, message: message))
    }
}

// In a root coordinator:
for await event in navigationCoordinator.eventStream.asFlow() {
    switch event {
    case .presentAlert(let title, let message):
        showAlert(title: title, message: message)
    case .navigateToDetail(let productID):
        navigator.push(ProductDetailScreen(productID: productID))
    case .dismissCurrentScreen:
        navigator.pop()
    }
}
```

### 4. Testing a flow pipeline

```swift
import Testing
import Flow
import FlowTesting

@Test("article feed emits cached then fresh")
func articleFeedEmitsCachedThenFresh() async throws {
    let feed = ThrowingFlow<[Article]> { collector in
        try await collector.emit([.cached])
        try await collector.emit([.cached, .fresh])
    }

    try await feed.test { tester in
        try await tester.expectValue([.cached])
        try await tester.expectValue([.cached, .fresh])
        try await tester.expectCompletion()
    }
}
```

## What's inside

### Cold streams

`Flow<T>` and `ThrowingFlow<T>` are cold async stream types. Each collector gets its own execution of the body closure. Builders include `of:`, sequence init, `empty`, `never`, and `asFlow()`. `FlowScope` handles lifetime, and `launch(in:)` ties collection to it.

### Hot streams

`StateFlow` / `MutableStateFlow` give you a current value with built-in deduplication. `SharedFlow` / `MutableSharedFlow` broadcast to multiple subscribers with concurrent delivery and a configurable replay buffer. Convert cold to hot with `asStateFlow(initialValue:strategy:)` or `asSharedFlow(replay:strategy:)` using `.eager`, `.lazy`, or `.whileSubscribed`.

### Operators

- **Transform**: `map`, `compactMap`, `filter`, `transform`, `prefix`, `dropFirst`, `scan`.
- **Lifecycle**: `onStart`, `onEach`, `onCompletion`.
- **Flattening**: `flatMap`, `flatMap(maxConcurrent:)`, `flatMapLatest`.
- **Combining**: `zip`, `combineLatest`, `merge`.
- **Error handling**: `catch`, `retry`, `retryWhen`.
- **Rate-limiting**: `debounce`, `throttle`, `removeDuplicates`, `sample`.
- **Buffering**: `buffer`, `keepingLatest`.
- **Terminal**: `collectLatest`, `first`, `exactlyOne`, `toArray`, `reduce`.

### UI integration

`import FlowUI` gets you the SwiftUI `@CollectedState` property wrapper, `ObservedStateFlow` with `isolated deinit`, the `View.collecting` extension, and `Flow(observing:_:)` for `@Observable` types. On UIKit/AppKit, `UIViewController.flowScope`, `NSViewController.flowScope`, and `NSWindowController.flowScope` tie collection to view controller lifetimes.

### Testing

`FlowTester`, `ThrowingFlowTester`, and `TestScope` drive assertions against flows. `TestClock` gives deterministic virtual time for rate-limiting and sharing operators. Everything plugs in through the `Flow.test(timeout:_:)` extension.

## Contributing

If your change touches anything in `Sources/Flow/Documentation.docc/`, regenerate the static site before opening a PR:

```bash
rm -rf docs
swift package --allow-writing-to-directory ./docs \
    generate-documentation --target Flow \
    --disable-indexing \
    --transform-for-static-hosting \
    --hosting-base-path FlowKit \
    --output-path ./docs
```

Commit both the source change and the regenerated `docs/` directory in the same PR.

## License

MIT. See [LICENSE](LICENSE).
