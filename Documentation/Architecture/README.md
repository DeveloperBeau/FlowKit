# Architecture

How the FlowKit modules fit together, taken from `Sources/` and `Package.swift`. Behaviour that the DocC catalogue already teaches is linked, not repeated.

The rules these modules follow are in [standards.md](../../standards.md).

| Page | What it covers |
|---|---|
| [Cold flows](ColdFlows.md) | `Flow`, `ThrowingFlow`, channels, `FlowScope` |
| [Hot flows](HotFlows.md) | `StateFlow`, `SharedFlow`, sharing |
| [Operators](Operators.md) | The operator library and cancellation |
| [Async bridge](AsyncBridge.md) | `AsyncSequence` and `AsyncStream` |
| [FlowTesting](FlowTesting.md) | `probing`, `TestClock`, virtual time |
| [FlowUI](FlowUI.md) | SwiftUI, UIKit, and AppKit |

## Rings

Dependencies point inward. `Flow` is the core product. `FlowTesting` and `FlowUI` depend on it, and neither depends on the other. `Flow` does not depend on them.

`FlowSharedModels` is the innermost target (`Mutex`, `BufferOverflow`, `SharingStrategy`, `FlowTestError`). `FlowCore` and `FlowTestClock` sit on it. `FlowOperators` sits on `FlowCore` and on AsyncAlgorithms. `FlowHotStreams` sits on the core, the operators, and the shared models. The `Flow` umbrella re-exports those four.

`FlowTestingCore` depends on the `Flow` product and on `FlowTestClock`. The `FlowTesting` umbrella re-exports `FlowSharedModels`, `FlowTestClock`, and `FlowTestingCore`.

`FlowSwiftUI` depends on `Flow` and on the hot-stream and core targets it uses directly. `FlowUIKitBridge` depends on `FlowCore` and `FlowHotStreams`. The `FlowUI` umbrella re-exports both bridges and `Flow`. The bridge files also import `FlowOperators`. That edge is recorded in [standards.md](../../standards.md).

No test in the repo fails the build when a target imports outward.

## Catalogue

The teaching articles live in the DocC catalogue:

- [Hot vs cold streams](https://developerbeau.github.io/FlowKit/documentation/flow/hotvscoldstreams)
- [Flow vs ThrowingFlow](https://developerbeau.github.io/FlowKit/documentation/flow/flowvsthrowingflow)
- [Cancellation](https://developerbeau.github.io/FlowKit/documentation/flow/cancellationsemantics)
- [Lifecycle-aware collection](https://developerbeau.github.io/FlowKit/documentation/flow/lifecycleawarecollection)
- [Kotlin Flow migration](https://developerbeau.github.io/FlowKit/documentation/flow/kotlinflowmigration)

The same articles are the markdown files under `Sources/Core/Flow/Documentation.docc/Articles/`.
