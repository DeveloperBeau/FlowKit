# Lifecycle-Aware Collection

Bind flow lifetimes to UI objects so collection starts when a view appears and stops automatically when it disappears.

## Overview

A flow that outlives its view wastes CPU, battery, and memory. A flow that stops too early drops events the user should see. FlowKit provides first-class lifecycle hooks for SwiftUI, UIKit, and AppKit so the right thing happens without manual cancellation calls.

## SwiftUI: @CollectedState

``FlowSwiftUI/CollectedState`` is a `DynamicProperty` that integrates with SwiftUI's view update cycle. SwiftUI calls `update()` when the view appears; `@CollectedState` starts collecting there. When the view is removed from the hierarchy, the underlying `Task` is cancelled.

```swift
// The flow starts collecting when SessionBanner appears in the view hierarchy.
// It cancels automatically when the view disappears. No manual cleanup.
struct SessionBanner: View {
    @CollectedState(SessionManager.shared.sessionState)
    var session: SessionState = .signedOut

    var body: some View {
        switch session {
        case .signedIn(let user):
            Label(user.displayName, systemImage: "person.circle.fill")
        case .signingIn:
            ProgressView("Signing in…")
        case .signedOut:
            EmptyView()
        case .error(let message):
            Text(message).foregroundStyle(.red)
        }
    }
}
```

The initial value (`.signedOut`) is displayed synchronously on the first render; subsequent values from the `StateFlow` drive re-renders.

### Animated updates

Pass an `animation` parameter to animate state transitions:

```swift
struct FeedView: View {
    // Posts slide in/out with a spring animation when the feed updates.
    @CollectedState(feedViewModel.posts, animation: .spring(duration: 0.3))
    var posts: [Post] = []

    var body: some View {
        List(posts) { PostRow(post: $0) }
    }
}
```

### Working with cold flows

`@CollectedState` requires a `StateFlow`, but you can convert any cold flow using `asStateFlow` in the view model:

```swift
@Observable
@MainActor
final class LocationViewModel {
    // Convert the cold location flow to a StateFlow once, here.
    // The sharing strategy keeps the GPS session alive for 5 seconds
    // after the map view disappears, in case of a brief navigation pop.
    let currentLocation: any StateFlow<CLLocation> = locationManager.updates
        .asStateFlow(
            initialValue: locationManager.lastLocation,
            strategy: .whileSubscribed(stopTimeout: .seconds(5))
        )
}

struct MapView: View {
    let viewModel: LocationViewModel

    @CollectedState(viewModel.currentLocation)
    var location: CLLocation = CLLocation(latitude: 0, longitude: 0)

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(center: location.coordinate, ...)))
    }
}
```

## UIKit: flowScope

`UIViewController.flowScope` returns a ``FlowCore/FlowScope`` stored as an associated object. Because `OBJC_ASSOCIATION_RETAIN_NONATOMIC` ties the scope's lifetime to the view controller's, the scope deallocates and cancels all tasks when the view controller is released.

```swift
final class ChatViewController: UIViewController {
    private let viewModel: ChatViewModel

    override func viewDidLoad() {
        super.viewDidLoad()

        // Convenience method: collects a StateFlow on the main actor.
        collect(viewModel.messages) { [weak self] messages in
            self?.tableView.apply(messages)
        }

        // For cold flows or more complex pipelines, use launch(in:) directly.
        viewModel.typingIndicators
            .throttle(for: .milliseconds(500))
            .onEach { [weak self] users in
                await MainActor.run { self?.updateTypingBanner(users) }
            }
            .launch(in: flowScope)
    }
    // viewController.flowScope.deinit fires when this VC is deallocated,
    // cancelling both tasks launched above.
}
```

### When the view controller stays in memory but should stop

If your architecture keeps view controllers in a stack and you want to stop collection when they leave the screen (not just when they deallocate), cancel and recreate the scope manually:

```swift
override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    flowScope.cancel()
}

override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    // Re-attach flows; flowScope.cancel() means a new scope is needed.
    // In practice, consider using a separate scope property for this pattern.
    startCollecting()
}
```

For most cases, letting deallocation handle it is simpler and correct.

## AppKit: NSViewController.flowScope and NSWindowController.flowScope

AppKit gets the same associated-object pattern. Both `NSViewController` and `NSWindowController` have a `flowScope` property:

```swift
final class ArticleWindowController: NSWindowController {
    private let viewModel: ArticleViewModel

    override func windowDidLoad() {
        super.windowDidLoad()

        // Collection is cancelled when the window controller deallocates.
        viewModel.articleState.asFlow()
            .onEach { [weak self] state in
                await MainActor.run { self?.render(state) }
            }
            .launch(in: flowScope)
    }
}

final class SidebarViewController: NSViewController {
    private let navigationCoordinator: NavigationCoordinator

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationCoordinator.currentSection.asFlow()
            .onEach { [weak self] section in
                await MainActor.run { self?.highlightSection(section) }
            }
            .launch(in: flowScope)
    }
}
```

## Manual: flow.launch(in: scope) for custom lifetimes

`launch(in:)` works with any ``FlowCore/FlowScope`` you own. This is the escape hatch for objects that don't fit the standard UIKit/AppKit patterns, such as custom coordinators, service objects with explicit start/stop semantics, and long-running background processors:

```swift
// A paginated feed that stops when the user navigates away from the section,
// not when the coordinator deallocates (which might be never).
actor FeedCoordinator {
    private var feedScope: FlowScope?

    func startFeed(for section: Section) {
        feedScope?.cancel()
        let scope = FlowScope()
        feedScope = scope

        feedRepository.paginatedFeed(section: section)
            .onEach { [weak self] page in await self?.appendPage(page) }
            .launch(in: scope)
    }

    func stopFeed() {
        feedScope?.cancel()
        feedScope = nil
    }
}
```

The scope is a value you create, own, and cancel on your timeline.

## The long-lived singleton pitfall

The most dangerous pattern is launching a flow in a scope that never cancels:

```swift
// BAD: the singleton's scope lives for the app's entire lifetime.
class AnalyticsService {
    static let shared = AnalyticsService()
    private let scope = FlowScope()

    init() {
        // This flow runs forever. Fine for truly app-lifetime work.
        // But if you add more flows here over time without auditing,
        // you accumulate tasks that never stop.
        userBehaviorFlow
            .onEach { event in await self.track(event) }
            .launch(in: scope)
    }
}
```

This is fine for genuinely app-lifetime flows (telemetry, crash reporting). It becomes a problem when a "temporary" flow gets launched in the singleton and never cleaned up. Use explicit scope lifetimes, or cancel and recreate scopes for bounded work:

```swift
// GOOD: scoped to a user session, not the app lifetime.
class AnalyticsService {
    static let shared = AnalyticsService()
    private var sessionScope: FlowScope?

    func startSession(for user: User) {
        sessionScope?.cancel()
        let scope = FlowScope()
        sessionScope = scope

        userBehaviorFlow(for: user)
            .onEach { event in await self.track(event, user: user) }
            .launch(in: scope)
    }

    func endSession() {
        sessionScope?.cancel()
        sessionScope = nil
    }
}
```

## Related concepts

- <doc:CancellationSemantics>: how cancellation propagates from scope through task to flow body
- <doc:HotVsColdStreams>: why `whileSubscribed` strategy pairs well with lifecycle-aware collection
