# FlowUI

Add `import FlowUI`. It re-exports `Flow`, so one import is enough. The SwiftUI and controller APIs
are `@MainActor`, and their action closures run on the main actor. `Flow(observing:)` is not
`@MainActor`. It uses the isolation of the caller.

| API | Use it when |
|---|---|
| `@CollectedState(wrappedValue, stateFlow, animation:)` | A SwiftUI view shows the current value of a `StateFlow`. Give an initial value. `animation` is optional. It needs iOS 17, macOS 14, tvOS 17, watchOS 10 or visionOS 1 or later (`@available`). |
| `View.collecting(_ flow:priority:action:)` | A SwiftUI view reacts to each value of a cold `Flow` (a side effect, not state). It collects while the view is on screen and cancels on disappear. |
| `Flow(observing: root, \.keyPath)` | You need a `Flow` of an `@Observable` object's property. `Element: Equatable`. It observes on the actor that makes it. |
| `UIViewController` / `NSViewController` `collect(_:action:)` | UIKit or AppKit code collects a `StateFlow` or a `Flow`. The work stops when the controller deallocates. The controller holds the scope, the scope holds the task, and the task holds the action, so capture `[weak self]` in the action. A strong `self` keeps the controller alive and the collection never stops. |
| `flowScope` on `UIViewController`, `NSViewController`, `NSWindowController` | You need a `FlowScope` tied to the controller: `flow.launch(in: flowScope)`. The same cycle applies, so capture `[weak self]` in `onEach`. |
| `ObservedStateFlow` | An `@Observable` holder of a `StateFlow` value for your own wrapper. `@CollectedState` uses it. Its `UpdatePolicy` is `.immediate`, `.animated(_:)` or `.transaction(_:)`. `@CollectedState` exposes only `animation:`. |

## Availability and limits

- UIKit `collect` and `flowScope` are not available on watchOS (`canImport(UIKit) && !os(watchOS)`).
  AppKit `collect` and `flowScope` are not available on Mac Catalyst.
- `@CollectedState` and `Flow(observing:)` need iOS 17, macOS 14, tvOS 17, watchOS 10 or visionOS 1.
  The package minimum is lower, so mark a view with `@available` or raise the target.
- A property wrapper cannot read another property when it is initialised. Do not write
  `@CollectedState(viewModel.results) var state` in a view that has `viewModel` as a property. Create
  the wrapper in `init` with `_state = CollectedState(wrappedValue: ..., viewModel.results)`.
- The `source` argument of `@CollectedState` is an `@autoclosure`. SwiftUI makes the view value
  again many times. Keep the flow in a model that lives longer than the view.
- Every value goes through `MainActor.run` in the controller `collect`. The action runs on the main
  actor, so a slow action slows the flow. Add `keepingLatest()` before it for a fast source.
- `Flow(observing:)` needs a `Sendable` key path. The compiler does not make `KeyPath` `Sendable`, so
  add `extension KeyPath: @retroactive @unchecked Sendable {}` in your module. Change the observed
  property on the same actor that observes it. A change from another actor can be missed.

## SwiftUI

```swift
import SwiftUI
import FlowUI

enum SessionState: Sendable, Equatable {
    case signedOut
    case signedIn(String)
}

@MainActor
final class SessionModel {
    private let state = MutableStateFlow<SessionState>(.signedOut)
    var sessionState: any StateFlow<SessionState> { state }
    func signIn(name: String) { state.send(.signedIn(name)) }
}

struct SessionView: View {
    @CollectedState var session: SessionState

    // A wrapper cannot read another property when it is initialised, so create it here.
    init(model: SessionModel) {
        _session = CollectedState(wrappedValue: .signedOut, model.sessionState)
    }

    var body: some View {
        Text(String(describing: session))
    }
}
```

```swift
import SwiftUI
import FlowUI

struct ToastView: View {
    let events: Flow<String>
    @State private var message = ""

    var body: some View {
        Text(message)
            .collecting(events) { message = $0 }
    }
}
```

## Observable objects

```swift
import Observation
import FlowUI

// Flow(observing:) needs a Sendable key path, and the compiler does not make
// KeyPath Sendable. This retroactive conformance is safe: key paths are immutable.
extension KeyPath: @retroactive @unchecked Sendable {}

@Observable
final class Counter: @unchecked Sendable {
    var count = 0
}

// Observation runs on the actor that makes the flow. Change `count` on that actor.
@MainActor
func countChanges(of counter: Counter) -> Flow<Int> {
    Flow(observing: counter, \.count)
}
```

## UIKit

```swift
import UIKit
import FlowUI

enum Phase: Sendable, Equatable {
    case idle
    case busy
}

final class PhaseViewController: UIViewController {
    private let phase: any StateFlow<Phase>

    init(phase: any StateFlow<Phase>) {
        self.phase = phase
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Capture self weakly: the controller holds the scope, the scope holds the task.
        collect(phase) { [weak self] value in
            self?.title = String(describing: value)
        }
    }
}
```

## AppKit

```swift
import AppKit
import FlowUI

final class StatusViewController: NSViewController {
    private let status: any StateFlow<String>

    init(status: any StateFlow<String>) {
        self.status = status
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        collect(status) { [weak self] text in
            self?.title = text
        }
    }
}
```
