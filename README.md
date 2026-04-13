# FlowKit

[![Swift 6.3](https://img.shields.io/badge/Swift-6.3-orange.svg)](https://swift.org)
[![Xcode 26.4](https://img.shields.io/badge/Xcode-26.4+-blue.svg)](https://developer.apple.com/xcode/)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2016%2B%20%7C%20macOS%2013%2B%20%7C%20tvOS%2016%2B%20%7C%20watchOS%209%2B%20%7C%20visionOS%201%2B-brightgreen.svg)](https://swift.org/platform-support/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Kotlin Flow semantics in Swift, with Swift-idiomatic API.**

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

## What's in 0.4.0

- **FlowUI umbrella** — `import FlowUI` gets SwiftUI, UIKit/AppKit bridges, and Flow.
- **SwiftUI** — `@CollectedState` property wrapper, `ObservedStateFlow` with `isolated deinit`, `View.collecting` extension, `Flow(observing:_:)` for `@Observable` types.
- **UIKit bridge** — `UIViewController.flowScope` (iOS/tvOS/Catalyst) with `collect` helpers.
- **AppKit bridge** — `NSViewController.flowScope` + `NSWindowController.flowScope` (macOS).

## What's in 0.3.0

- **Rate-limiting operators** — `debounce`, `throttle`, `removeDuplicates`, `sample`.
- **Buffering operators** — `buffer`, `keepingLatest`.
- **Terminal operators** — `collectLatest`, `first`, `exactlyOne`, `toArray`, `reduce`.

## What's in 0.2.0

- **Flattening operators** — `flatMap`, `flatMap(maxConcurrent:)`, `flatMapLatest`.
- **Combining operators** — `zip`, `combineLatest`, `merge`.
- **Error handling operators** — `catch`, `retry`, `retryWhen`.

## What's in 0.1.0

- **`Flow<T>` and `ThrowingFlow<T>`** — cold async stream types with `collect`, builders (`of:`, sequence, `empty`, `never`, `asFlow`), `FlowScope`-based lifetime management, and `launch(in:)`.
- **Transform operators** — `map`, `compactMap`, `filter`, `transform`, `prefix`, `dropFirst`, `scan`.
- **Lifecycle operators** — `onStart`, `onEach`, `onCompletion`.
- **Hot streams** — `StateFlow` / `MutableStateFlow` with built-in deduplication; `SharedFlow` / `MutableSharedFlow` with concurrent delivery and configurable replay buffer.
- **Sharing strategies** — `asStateFlow(initialValue:strategy:)` and `asSharedFlow(replay:strategy:)` with `.eager`, `.lazy`, and `.whileSubscribed(stopTimeout:replayExpiration:)`.
- **Testing infrastructure** — `FlowTester`, `ThrowingFlowTester`, `TestScope`, `TestClock` for deterministic virtual-time tests, `Flow.test(timeout:_:)` extension.

## Coming soon

- **0.2.0** — Flattening (`flatMap`, `flatMapLatest`), combining (`zip`, `combineLatest`, `merge`), error handling (`catch`, `retry`, `retryWhen`).
- **0.3.0** — Rate-limiting (`debounce`, `throttle`, `removeDuplicates`), buffering (`buffer`, `keepingLatest`), terminal operators (`collectLatest`, `first`, `exactlyOne`, `toArray`, `reduce`).
- **0.4.0** — `FlowUI` target with SwiftUI `@CollectedState`, UIKit/AppKit bridges, and `@Observable` interop.
- **0.5.0** — API freeze, complete DocC catalog, tutorials.
- **1.0.0** — Stable release.

## License

MIT — see [LICENSE](LICENSE).
