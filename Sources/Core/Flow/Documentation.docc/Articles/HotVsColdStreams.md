# Hot vs Cold Streams

Cold streams run once per collector. Hot streams share a single execution across all collectors. Choosing the right kind prevents duplicate network requests, dropped events, and stale state.

## Overview

The cold/hot distinction is the most important mental model in FlowKit. Get it wrong and you'll see duplicate side effects (a cold flow collected by two views fires its API call twice) or missed events (a late subscriber to a cold event flow never sees events that happened before it attached).

## Cold streams: new execution per collector

``FlowCore/Flow`` and ``FlowCore/ThrowingFlow`` are cold. The body closure runs from the beginning each time `collect` is called. There is no shared state between collectors.

```swift
// This flow body runs independently for every collect() call.
let searchResults: ThrowingFlow<[Product]> = productRepository.search("boots")

// First collector. Triggers one network request.
try await searchResults.collect { products in displayResults(products) }

// Second collector. Triggers a second, completely independent network request.
try await searchResults.collect { products in logResults(products) }
```

For flows that wrap a single logical operation (one network request, one database query), being cold is exactly what you want: the caller controls when work starts, and there's no implicit shared state. Two SwiftUI previews collecting the same flow get their own independent data.

Cold flows are also **lazy**: no work happens until `collect` is called. You can build a complex operator chain, pass it around, and nothing executes until a subscriber attaches.

## Hot streams: shared execution, multicast delivery

Hot streams run their upstream once and deliver each emission to all current subscribers. ``FlowHotStreams/StateFlow`` and ``FlowHotStreams/SharedFlow`` are the two hot primitives in FlowKit.

```swift
// MutableStateFlow is hot: created once, all collectors see the same value.
let connectionStatus = MutableStateFlow<ConnectionStatus>(.disconnected)

// Two collectors both receive every status change from the same source.
connectionStatus.asFlow().collect { status in updateStatusBar(status) }
connectionStatus.asFlow().collect { status in logStatus(status) }
```

Converting a cold flow to a hot one uses `asStateFlow` or `asSharedFlow`:

```swift
// Start location updates once; share with the map view and the analytics layer.
let liveLocation: any StateFlow<CLLocation> = locationUpdates
    .asStateFlow(initialValue: lastKnownLocation, strategy: .whileSubscribed(stopTimeout: .seconds(5)))
```

The upstream (`locationUpdates`) runs exactly once, regardless of how many views collect `liveLocation`.

## StateFlow: current-value semantics

``FlowHotStreams/StateFlow`` always holds the most recent value. A new subscriber receives the current value immediately upon attaching and never misses the "current state."

Use `StateFlow` for **current things**: auth session, network connectivity, form validation state, the currently-playing track.

```swift
// SessionManager uses StateFlow because "current session" is always meaningful.
actor SessionManager {
    let sessionState: any StateFlow<SessionState>

    private let _state = MutableStateFlow<SessionState>(.signedOut)

    init(authService: AuthService) {
        sessionState = _state.asStateFlow()

        Task {
            for await event in authService.events {
                switch event {
                case .signedIn(let session): await _state.send(.signedIn(session))
                case .tokenRefreshFailed: await _state.send(.error("Session expired"))
                case .signedOut: await _state.send(.signedOut)
                }
            }
        }
    }
}
```

Any view that collects `sessionState` immediately receives the current auth state. There is no window where it's "waiting for the first event."

## SharedFlow: event semantics

``FlowHotStreams/SharedFlow`` does not hold state. It broadcasts each event to all current subscribers, and late subscribers miss events that fired before they attached (unless a replay buffer is configured).

Use `SharedFlow` for **things that happened**: navigation commands, one-shot errors, analytics events, chat messages in a room.

```swift
// NavigationCoordinator uses SharedFlow because navigation is an event, not state.
actor NavigationCoordinator {
    private let _events = MutableSharedFlow<NavigationEvent>()
    var events: any SharedFlow<NavigationEvent> { _events }

    func navigate(to destination: Destination) async {
        await _events.emit(NavigationEvent.push(destination))
    }

    func navigateBack() async {
        await _events.emit(NavigationEvent.pop)
    }
}

// UIKit root coordinator listens for events and drives the nav stack.
final class RootCoordinator {
    private let scope = FlowScope()

    func start() {
        navigationCoordinator.events.asFlow()
            .onEach { [weak self] event in self?.handle(event) }
            .launch(in: scope)
    }
}
```

If a subscriber is not attached when an event fires, the event is lost. That's intentional for navigation: a navigation command issued while the coordinator is mid-transition should not be replayed when the transition finishes.

For chat messages, you'd want a replay buffer so users joining a room see recent history:

```swift
let recentMessages: any SharedFlow<ChatMessage> = messageStream
    .asSharedFlow(replay: 50, strategy: .whileSubscribed(stopTimeout: .seconds(30)))
```

## Cold + asSharedFlow vs MutableSharedFlow

Both produce a multicast stream, but they belong to different problems. Pick wrong and you end up either reinventing `SharingCoordinator` by hand or paying for it when you don't need it.

### Cold + `asSharedFlow` for stateful resources

When the source is a stateful resource (`CLLocationManager`, `WebSocket`, `NSFileCoordinator`, an audio session, a Bluetooth scanner), the start and stop are paired with subscriber lifecycle. Wrap a cold body inside `Flow { collector in ... }` that opens the resource on entry and tears it down via `withTaskCancellationHandler`, then expose it through `.asSharedFlow(replay:strategy:)`.

```swift
actor LocationTracker {
    nonisolated let locations: any SharedFlow<CLLocation>

    init() {
        self.locations = Self.coldLocationFlow
            .asSharedFlow(replay: 1, strategy: .whileSubscribed(stopTimeout: .zero))
    }

    private static var coldLocationFlow: Flow<CLLocation> {
        Flow { collector in
            let manager = CLLocationManager()
            // ...wire delegate, start updates, await cancellation...
        }
    }
}
```

The first subscriber starts the hardware. Additional subscribers share that one manager. Last unsubscribe stops it. A new subscriber later restarts it. `SharingCoordinator` does the ref counting for free.

### MutableSharedFlow for events you produce yourself

When there is no underlying resource to start or stop, just an event you generate from app code, use `MutableSharedFlow` directly. Navigation commands, toast triggers, button taps, "user signed out" broadcasts.

```swift
actor NavigationCoordinator {
    private let _events = MutableSharedFlow<NavigationEvent>(replay: 0)
    var events: any SharedFlow<NavigationEvent> { _events }

    func push(_ destination: Destination) async {
        await _events.emit(.push(destination))
    }
}
```

Nothing needs to start or stop based on subscriber count, so the lifecycle machinery would be wasted overhead.

### Decision shortcut

| Source of values | Pattern |
|------------------|---------|
| Stateful resource with start/stop semantics | Cold body + `.asSharedFlow(replay:strategy:)` |
| Events you `emit` from app code | `MutableSharedFlow` directly |
| Single current value with start/stop | Cold body + `.asStateFlow(initialValue:strategy:)` |
| Single current value you set from app code | `MutableStateFlow` directly |

If you find yourself observing `subscriptionCount` on a `MutableSharedFlow` to start or stop something, you want cold + `asSharedFlow` instead.

## Sharing strategies

When you convert a cold flow to a hot stream, the `SharingStrategy` controls when upstream collection starts and stops:

| Strategy | Upstream starts | Upstream stops | Use case |
|----------|----------------|----------------|----------|
| `.eager` | When the hot flow is created | When scope ends | Pre-warm auth state at app launch |
| `.lazy` | When first subscriber attaches | When scope ends | Background sync that should keep running once started |
| `.whileSubscribed(stopTimeout:)` | When first subscriber attaches | `stopTimeout` after last subscriber leaves | UI state that should pause when no views are showing it |

The recommended default for UI state is `.whileSubscribed(stopTimeout: .seconds(5))`. The 5-second window handles configuration changes (iPad split-view), tab switches, and brief navigation stack pops without tearing down and re-establishing the upstream pipeline.

```swift
// Location tracking: keep alive for 5s after last collector leaves,
// so a brief screen transition doesn't restart GPS acquisition.
let sharedLocation: any StateFlow<CLLocation> = locationFlow
    .asStateFlow(
        initialValue: .init(latitude: 0, longitude: 0),
        strategy: .whileSubscribed(stopTimeout: .seconds(5))
    )
```

## Summary

| Question | Answer | Type |
|----------|--------|------|
| Does every collector need independent data? | Yes | `Flow` / `ThrowingFlow` (cold) |
| Is this "the current value of X"? | Yes | `StateFlow` (hot) |
| Is this "an event that happened"? | Yes | `SharedFlow` (hot) |
| Should the upstream run before anyone subscribes? | Yes | `.eager` strategy |
| Should the upstream stop when the last view disappears? | Yes | `.whileSubscribed` |

## Related concepts

- <doc:FlowVsThrowingFlow>: choosing between the two cold stream types
- <doc:LifecycleAwareCollection>: binding hot stream collection to view lifetimes
- <doc:CancellationSemantics>: how cancellation propagates through hot streams
