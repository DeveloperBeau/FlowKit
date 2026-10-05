import Testing
import Foundation
import FlowSharedModels
import FlowTestClock
import FlowTestSupport
@testable import FlowTestingCore

/// Blocks the calling thread, as a stalled process would.
private func stall(seconds: TimeInterval) {
    Thread.sleep(forTimeInterval: seconds)
}

/// Runs a `waitUntil` whose condition never holds and reports, through
/// `finished`, when it returns. `started` fires on the first poll, which is
/// after the deadline has been fixed on the clock.
private func startNeverHoldingWait(
    timeout: Duration,
    clock: TestClock,
    started: Signal,
    finished: Signal
) -> Task<Void, Never> {
    Task {
        await waitUntil(timeout: timeout, clock: clock) {
            started.fire()
            return false
        }
        finished.fire()
    }
}

@Suite("waitUntil")
struct WaitUntilTests {
    @Test("Returns as soon as the condition holds")
    func returnsWhenConditionHolds() async {
        let clock = TestClock()
        let calls = Mutex(0)
        await waitUntil(clock: clock) { calls.withLock { $0 += 1; return $0 >= 3 } }
        #expect(calls.withLock { $0 } == 3)
        #expect(clock.now.offset == .zero)
    }

    @Test("A condition that never holds returns once the clock reaches the timeout")
    func neverHoldingConditionReturnsAtTheDeadline() async {
        let clock = TestClock()
        let started = Signal()
        let finished = Signal()
        let wait = startNeverHoldingWait(timeout: .seconds(5), clock: clock, started: started, finished: finished)

        await started.wait()
        await clock.advance(by: .seconds(5) - .milliseconds(1))
        #expect(!finished.hasFired, "the wait gave up before the clock reached its timeout")

        await clock.advance(by: .milliseconds(1))
        await wait.value
        #expect(finished.hasFired)
    }

    @Test("A clock jump past the timeout is not treated as a stall")
    func clockJumpExpiresTheTimeout() async {
        let clock = TestClock()
        let started = Signal()
        let finished = Signal()
        let wait = startNeverHoldingWait(timeout: .seconds(5), clock: clock, started: started, finished: finished)

        await started.wait()
        await clock.advance(by: .seconds(60))
        await wait.value
        #expect(finished.hasFired, "a jump of more than a second extended the deadline like a stall")
    }

    @Test("Keeps polling past the yield spins until the condition holds")
    func keepsPollingUntilTheConditionHolds() async {
        let clock = TestClock()
        let calls = Mutex(0)
        await waitUntil(timeout: .seconds(5), clock: clock) { calls.withLock { $0 += 1; return $0 >= 80 } }
        #expect(calls.withLock { $0 } == 80, "the wait returned before the condition held")
    }

    // The real-clock overload, kept as a deliberate real-time path: the stall
    // injector proves the stall allowance, which only exists on the real clock.
    @available(*, deprecated)
    private func legacyWaitUntil(
        timeout: Duration,
        _ condition: @Sendable () async -> Bool
    ) async {
        await waitUntil(timeout: timeout, condition)
    }

    @available(*, deprecated)
    @Test("The real-clock wait returns after its timeout when the condition never holds")
    func legacyNeverHoldingConditionReturns() async {
        let calls = Mutex(0)
        await legacyWaitUntil(timeout: .milliseconds(1)) { calls.withLock { $0 += 1 }; return false }
        #expect(calls.withLock { $0 } >= 1)
    }

    @available(*, deprecated)
    @Test("A stall inside the real-clock wait does not use up the timeout")
    func legacyStallDoesNotExpireTheTimeout() async {
        let calls = Mutex(0)
        await legacyWaitUntil(timeout: .milliseconds(100)) {
            let call = calls.withLock { $0 += 1; return $0 }
            if call == 1 { stall(seconds: 1.5) }
            return call >= 3
        }
        #expect(calls.withLock { $0 } == 3, "the wait gave up after the stall instead of polling on")
    }
}
