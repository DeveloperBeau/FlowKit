# FlowUI

`FlowUI` is the Apple UI product. It re-exports `FlowSwiftUI`, `FlowUIKitBridge`, and `Flow`. It depends on `Flow` and never the other way around. It does not depend on `FlowTesting`.

The SwiftUI, Observation, UIKit, and AppKit sources are wrapped in `canImport`. The `FlowUI` umbrella re-exports those targets with no platform check. Where the imports are false the targets compile empty. That is why `FlowUI` is not a product on Android. `Flow` and `FlowTesting` are the products that build there.

UI actions run on the main actor. Core operators do not change isolation. The catalogue article [Lifecycle-aware collection](https://developerbeau.github.io/FlowKit/documentation/flow/lifecycleawarecollection) shows the call sites. This page is the ownership of those types.

## SwiftUI

`CollectedState` is a `DynamicProperty` and a property wrapper, available from iOS 17, macOS 14, tvOS 17, watchOS 10, and visionOS 1. SwiftUI calls `update()` when the view appears, and `update()` starts collection. The wrapped value is the latest element. The initializer takes an initial value, a `StateFlow`, and an optional `Animation`.

`ObservedStateFlow` is the `@Observable` object `CollectedState` stores. It is `@MainActor`. `value` starts at the initial value and changes when the flow emits a different one. `UpdatePolicy` is `immediate`, `animated`, or `transaction`. `start()` begins collection if it has not started. `stop()` clears the active flag and cancels the task.

The collection task captures the source and a weak reference to the observer. A strong capture would keep the observer alive, so its teardown would never run. The task is held by `CancellingTask`, and that helper's `deinit` cancels the task. The class has no `isolated deinit`, because that deinit crashes the Swift 6.3 optimizer in release builds.

`View.collecting` collects a cold `Flow` for the view's lifetime and cancels when the view disappears. The SwiftUI `task` modifier sits inside a private `CollectingModifier`. Returning `.task` directly made a release build reference that overload's opaque type from the client, and linking failed on deployment targets older than the overload. The action is `@MainActor`.

`Flow(observing:_:)` in `FlowObservingInit.swift` emits an `@Observable` key path, then emits again when it changes. Observation runs on the caller's actor (`#isolation`). Delivery stays reliable when the object is mutated on that same actor. A mutation from another actor can fall between the tracking windows.

## UIKit and AppKit

`UIViewController.flowScope` is a `FlowScope` stored as an associated object, created on first access. The key is a private stateless global. Releasing the view controller releases the scope, and the scope's `deinit` cancels its tasks. The file is compiled where UIKit exists and the target is not watchOS.

On `UIViewController` and `NSViewController`, `collect` for a `StateFlow` or a `Flow` runs `onEach`, hops the action to the main actor, and `launch`es in `flowScope`. The `onEach` call is why these files import `FlowOperators`.

`NSViewController` has `flowScope` and `collect`. `NSWindowController` has `flowScope` only. Both are compiled where AppKit exists and the target is not Mac Catalyst. Each controller type has its own associated-object key.
