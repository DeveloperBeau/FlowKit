import Testing
import Foundation
import FlowSharedModels
@testable import FlowTestingCore

/// Blocks the calling thread, as a stalled process would.
private func stall(seconds: TimeInterval) {
    Thread.sleep(forTimeInterval: seconds)
}

@Suite("waitUntil")
struct WaitUntilTests {
    @Test("Returns as soon as the condition holds")
    func returnsWhenConditionHolds() async {
        let calls = Mutex(0)
        await waitUntil { calls.withLock { $0 += 1; return $0 >= 3 } }
        #expect(calls.withLock { $0 } == 3)
    }

    @Test("A condition that never holds returns after the timeout")
    func neverHoldingConditionReturns() async {
        let calls = Mutex(0)
        await waitUntil(timeout: .milliseconds(50)) { calls.withLock { $0 += 1 }; return false }
        #expect(calls.withLock { $0 } > 1, "the condition was polled until the timeout, then the wait returned")
    }

    @Test("A stall inside the wait does not use up the timeout")
    func stallDoesNotExpireTheTimeout() async {
        let calls = Mutex(0)
        await waitUntil(timeout: .milliseconds(100)) {
            let call = calls.withLock { $0 += 1; return $0 }
            if call == 1 { stall(seconds: 1.5) }
            return call >= 3
        }
        #expect(calls.withLock { $0 } == 3, "the wait gave up after the stall instead of polling on")
    }
}
