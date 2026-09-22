#if canImport(SwiftUI)
import Testing
import SwiftUI
import FlowCore
import FlowSharedModels
@testable import FlowSwiftUI

@Suite("View.collecting")
@MainActor
struct ViewExtensionsTests {
    @Test("View.collecting returns a View")
    func returnsView() {
        let flow = Flow(of: 1, 2, 3)
        let view = Text("hi").collecting(flow) { _ in }
        // Compile check. The modifier applies.
        _ = view
    }

    @Test("_collectFlow drives collection and forwards values to action")
    func collectFlowHelper() async {
        let received = Mutex<[Int]>([])
        let flow = Flow<Int> { collector in
            await collector.emit(1)
            await collector.emit(2)
            await collector.emit(3)
        }
        await _collectFlow(flow) { value in
            received.withLock { $0.append(value) }
        }
        #expect(received.withLock { $0 } == [1, 2, 3])
    }

    @Test("_collectFlow with empty flow completes without invoking action")
    func collectFlowEmpty() async {
        let calls = Mutex(0)
        let flow = Flow<Int>.empty
        await _collectFlow(flow) { _ in
            calls.withLock { $0 += 1 }
        }
        #expect(calls.withLock { $0 } == 0)
    }
}
#endif
