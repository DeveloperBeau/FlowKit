---
name: flowkit
description: How FlowKit flows behave in code that uses them. Use when you write, change, review or test Swift code that uses Flow, ThrowingFlow, callbackFlow, channelFlow, MutableStateFlow, MutableSharedFlow, asStateFlow, asSharedFlow, FlowRecorder or the FlowTesting module.
---

# FlowKit

FlowKit gives Swift a cold stream type (`Flow`, `ThrowingFlow`) and two hot types
(`MutableStateFlow`, `MutableSharedFlow`). Its model follows Kotlin Flow. The facts in these files
come from the source and the tests of the package.

Import only the four products. The internal targets (`FlowCore`, `FlowOperators`, `FlowHotStreams`,
`FlowTestClock` and the others) are not products.

| Product | Use it when | Read |
|---|---|---|
| `Flow` | You build, transform, share or collect streams. It holds `Flow`, `ThrowingFlow`, the operators, `MutableStateFlow`, `MutableSharedFlow`, `FlowScope` and `Mutex`. | [Flow.md](Flow.md) |
| `FlowTesting` | You test flows in a test target. It re-exports `TestClock` and `FlowTestError`. It links the `Testing` framework. | [FlowTesting.md](FlowTesting.md) |
| `FlowRecording` | You record a flow in code that cannot link `Testing`, for example a UI-test host app or a preview. | [FlowTesting.md](FlowTesting.md) |
| `FlowUI` | A SwiftUI view, a UIKit controller or an AppKit controller observes a flow. It re-exports `Flow`. | [FlowUI.md](FlowUI.md) |

Package platforms: iOS 16, macOS 13, tvOS 16, watchOS 9 and visionOS 1. Some APIs need newer
versions. Each file names them.

Every ```swift block in these files compiles on its own. A block marked `swift-fragment` does not.
