import Testing
import Foundation
import FlowSharedModels
import FlowTestSupport
@testable import FlowTestClock

@Suite("TestClock waitForSleepers")
struct TestClockSleeperWaiterTests {
    private func sleeper(on clock: TestClock, seconds: Int) -> Task<Void, any Error> {
        Task { try await clock.sleep(until: TestClock.Instant(offset: .seconds(seconds)), tolerance: nil) }
    }

    @Test("Returns at once when enough sleepers are already registered")
    func returnsWhenAlreadySatisfied() async throws {
        let clock = TestClock()
        let first = sleeper(on: clock, seconds: 1)
        let second = sleeper(on: clock, seconds: 2)
        #expect(await clock.registersSleepers(2), "the sleepers never registered")

        // Both sleepers are registered now, so each of these is already satisfied.
        #expect(await clock.registersSleepers(1), "wait for 1 parked with 2 sleepers registered")
        #expect(await clock.registersSleepers(2), "wait for 2 parked with 2 sleepers registered")
        await clock.run()
        try await first.value
        try await second.value
    }

    @Test("A count of zero or less returns with no sleepers")
    func zeroReturnsImmediately() async throws {
        let clock = TestClock()
        #expect(await clock.registersSleepers(0), "wait for 0 parked on an empty clock")
        #expect(await clock.registersSleepers(-1), "wait for -1 parked on an empty clock")
    }

    @Test("Suspends until the requested number of sleepers has registered")
    func waitsForTheRequestedCount() async throws {
        let clock = TestClock()
        let resumed = Signal()
        let waiter = Task {
            try await clock.waitForSleepers(2)
            resumed.fire()
        }

        let first = sleeper(on: clock, seconds: 1)
        // Let the waiter see exactly one sleeper before the second arrives.
        await clock.advance(by: .zero)
        #expect(clock.sleeperCount == 1)
        #expect(!resumed.hasFired, "resumed with only one of two sleepers")

        let second = sleeper(on: clock, seconds: 2)
        try await waiter.value
        #expect(resumed.hasFired)

        await clock.run()
        try await first.value
        try await second.value
    }

    @Test("Resumes several waiters with different counts as their counts are met")
    func resumesEachWaiterAtItsCount() async throws {
        let clock = TestClock()
        let one = Signal()
        let two = Signal()
        let waiterOne = Task { try await clock.waitForSleepers(1); one.fire() }
        let waiterTwo = Task { try await clock.waitForSleepers(2); two.fire() }

        let first = sleeper(on: clock, seconds: 1)
        try await waiterOne.value
        await clock.advance(by: .zero)
        #expect(!two.hasFired, "the waiter for two resumed with one sleeper")

        let second = sleeper(on: clock, seconds: 2)
        try await waiterTwo.value

        await clock.run()
        try await first.value
        try await second.value
    }

    @Test("Cancelling the waiter throws CancellationError and leaves the clock usable")
    func cancellationThrows() async throws {
        let clock = TestClock()
        let started = Signal()
        let waiter = Task {
            started.fire()
            try await clock.waitForSleepers(1)
        }
        await started.wait()
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }

        // The cancelled waiter must not be resumed a second time by a later sleeper.
        let later = sleeper(on: clock, seconds: 1)
        try await clock.waitForSleepers(1)
        await clock.run()
        try await later.value
    }

    @Test("An already-cancelled task throws instead of waiting")
    func alreadyCancelledThrows() async {
        let clock = TestClock()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await clock.waitForSleepers(1)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test("A sleeper that is removed again does not satisfy a later wait")
    func removedSleeperDoesNotCount() async throws {
        let clock = TestClock()
        let cancelled = sleeper(on: clock, seconds: 1)
        try await clock.waitForSleepers(1)
        cancelled.cancel()
        _ = await cancelled.result
        #expect(clock.sleeperCount == 0)

        let resumed = Signal()
        let waiter = Task { try await clock.waitForSleepers(1); resumed.fire() }
        await clock.advance(by: .zero)
        #expect(!resumed.hasFired, "counted a sleeper that had already been cancelled")

        let live = sleeper(on: clock, seconds: 2)
        try await waiter.value
        await clock.run()
        try await live.value
    }

    // MARK: - Falling counts

    /// Runs `wait` in its own task and reports when it returns.
    private func startWaiter(
        _ wait: @escaping @Sendable () async throws -> Void
    ) -> (task: Task<Void, any Error>, returned: Signal) {
        let returned = Signal()
        let task = Task {
            try await wait()
            returned.fire()
        }
        return (task, returned)
    }

    @Test("waitForNoSleepers returns at once on a clock with no sleepers")
    func noSleepersReturnsImmediately() async {
        let clock = TestClock()
        let waiter = startWaiter { try await clock.waitForNoSleepers() }
        #expect(await waiter.returned.firesWithinHops(), "an empty clock kept the waiter parked")
        let atMost = startWaiter { try await clock.waitForSleepers(atMost: 3) }
        #expect(await atMost.returned.firesWithinHops(), "atMost 3 parked on an empty clock")
    }

    @Test("waitForNoSleepers resumes when an advance wakes the last sleeper")
    func noSleepersAfterAdvance() async throws {
        let clock = TestClock()
        let first = sleeper(on: clock, seconds: 1)
        let second = sleeper(on: clock, seconds: 2)
        #expect(await clock.registersSleepers(2), "the sleepers never registered")

        let none = startWaiter { try await clock.waitForNoSleepers() }
        let atMostOne = startWaiter { try await clock.waitForSleepers(atMost: 1) }
        #expect(!(await none.returned.firesWithinHops()), "returned with 2 sleepers")
        #expect(!(await atMostOne.returned.firesWithinHops()), "atMost 1 returned with 2 sleepers")

        await clock.advance(by: .seconds(1))
        #expect(await atMostOne.returned.firesWithinHops(), "atMost 1 did not return after one sleeper woke")
        #expect(!(await none.returned.firesWithinHops()), "returned with 1 sleeper left")

        await clock.advance(by: .seconds(1))
        #expect(await none.returned.firesWithinHops(), "did not return after the last sleeper woke")
        try await first.value
        try await second.value
    }

    @Test("waitForNoSleepers resumes when cancellation tears the last sleeper down")
    func noSleepersAfterCancellation() async throws {
        let clock = TestClock()
        let only = sleeper(on: clock, seconds: 1)
        try await clock.waitForSleepers(1)

        let none = startWaiter { try await clock.waitForNoSleepers() }
        #expect(!(await none.returned.firesWithinHops()), "returned with a live sleeper")

        only.cancel()
        #expect(await none.returned.firesWithinHops(), "did not return after the sleeper was cancelled")
    }

    @Test("Cancelling a waitForNoSleepers waiter throws CancellationError")
    func noSleepersCancellationThrows() async throws {
        let clock = TestClock()
        let live = sleeper(on: clock, seconds: 1)
        try await clock.waitForSleepers(1)

        let ended = Signal()
        let thrown = Mutex<(any Error)?>(nil)
        let task = Task {
            do { try await clock.waitForNoSleepers() } catch { thrown.withLock { $0 = error } }
            ended.fire()
        }
        // Give the waiter time to park, so the cancel reaches the handler
        // rather than the cancelled-before-waiting check.
        for _ in 0..<200 { await Task.yield() }
        task.cancel()
        #expect(await ended.firesWithinHops(), "a cancelled waiter stayed parked")
        #expect(thrown.withLock { $0 } is CancellationError)

        await clock.run()
        try await live.value
    }
}
