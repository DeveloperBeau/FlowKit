import Testing
import Foundation
import FlowSharedModels
import FlowTestSupport
import FlowTestingCore
@testable import FlowTestClock

@Suite("TestClock waitForSleepers")
struct TestClockSleeperWaiterTests {
    /// The result of a waiter task, read under a wall-clock safety net, or `nil` if the
    /// waiter never returned. The safety net never joins the waiter: a watcher task awaits
    /// it and fires a signal, and only the signal is awaited. So a waiter that ignores
    /// cancellation still fails by name. It is cancelled, recorded as "<name> never
    /// returned", and the run moves on.
    private func outcome(of task: Task<Void, any Error>, _ name: String) async -> Result<Void, any Error>? {
        guard await task.returns() else {
            Issue.record("\(name) never returned")
            return nil
        }
        return await task.result
    }

    /// Awaits a waiter task under a wall-clock safety net and rethrows its error. Returns
    /// `false` when the waiter never returned, after recording it by name, so the caller
    /// stops rather than run later steps against a broken setup.
    private func finishes(_ task: Task<Void, any Error>, _ name: String) async throws -> Bool {
        guard let result = await outcome(of: task, name) else { return false }
        try result.get()
        return true
    }

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

    @Test("registersSleepers waits for a sleeper that registers after many scheduler hops")
    func registersLateSleeper() async throws {
        let clock = TestClock()
        // The sleeper yields 10 times the old hop budget before it registers. A wait that
        // counts hops gives up first, and a wait that parks on the clock does not.
        let late = Task {
            for _ in 0..<10_000 { await Task.yield() }
            try await clock.sleep(until: TestClock.Instant(offset: .seconds(1)), tolerance: nil)
        }
        try #require(await clock.registersSleepers(1), "the late sleeper never registered")
        await clock.run()
        try await late.value
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
        try #require(await clock.registersSleepers(1), "the first sleeper never registered")
        #expect(clock.sleeperCount == 1)
        #expect(!resumed.hasFired, "resumed with only one of two sleepers")

        let second = sleeper(on: clock, seconds: 2)
        guard try await finishes(waiter, "the waiter for two sleepers") else { return }
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
        guard try await finishes(waiterOne, "the waiter for one sleeper") else { return }
        try #require(await clock.registersSleepers(1), "the first sleeper never registered")
        #expect(!two.hasFired, "the waiter for two resumed with one sleeper")

        let second = sleeper(on: clock, seconds: 2)
        guard try await finishes(waiterTwo, "the waiter for two sleepers") else { return }

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
        guard let result = await outcome(of: waiter, "the cancelled waiter") else { return }
        #expect(throws: CancellationError.self) { try result.get() }

        // The cancelled waiter must not be resumed a second time by a later sleeper.
        let later = sleeper(on: clock, seconds: 1)
        try #require(await clock.registersSleepers(1), "the later sleeper never registered")
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
        guard let result = await outcome(of: task, "the already-cancelled waiter") else { return }
        #expect(throws: CancellationError.self) { try result.get() }
    }

    @Test("A sleeper that is removed again does not satisfy a later wait")
    func removedSleeperDoesNotCount() async throws {
        let clock = TestClock()
        let cancelled = sleeper(on: clock, seconds: 1)
        try #require(await clock.registersSleepers(1), "the sleeper to cancel never registered")
        cancelled.cancel()
        _ = await cancelled.result
        #expect(clock.sleeperCount == 0)

        let resumed = Signal()
        let waiter = Task { try await clock.waitForSleepers(1); resumed.fire() }
        await clock.advance(by: .zero)
        #expect(!resumed.hasFired, "counted a sleeper that had already been cancelled")

        let live = sleeper(on: clock, seconds: 2)
        guard try await finishes(waiter, "the waiter for the live sleeper") else { return }
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
        #expect(await waiter.returned.fires(), "an empty clock kept the waiter parked")
        let atMost = startWaiter { try await clock.waitForSleepers(atMost: 3) }
        #expect(await atMost.returned.fires(), "atMost 3 parked on an empty clock")
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
        #expect(await atMostOne.returned.fires(), "atMost 1 did not return after one sleeper woke")
        #expect(!(await none.returned.firesWithinHops()), "returned with 1 sleeper left")

        await clock.advance(by: .seconds(1))
        #expect(await none.returned.fires(), "did not return after the last sleeper woke")
        try await first.value
        try await second.value
    }

    @Test("waitForNoSleepers resumes when cancellation tears the last sleeper down")
    func noSleepersAfterCancellation() async throws {
        let clock = TestClock()
        let only = sleeper(on: clock, seconds: 1)
        try #require(await clock.registersSleepers(1), "the only sleeper never registered")

        let none = startWaiter { try await clock.waitForNoSleepers() }
        #expect(!(await none.returned.firesWithinHops()), "returned with a live sleeper")

        only.cancel()
        #expect(await none.returned.fires(), "did not return after the sleeper was cancelled")
    }

    @Test("Cancelling a waitForNoSleepers waiter throws CancellationError")
    func noSleepersCancellationThrows() async throws {
        let clock = TestClock()
        let live = sleeper(on: clock, seconds: 1)
        try #require(await clock.registersSleepers(1), "the live sleeper never registered")

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
        #expect(await ended.fires(), "a cancelled waiter stayed parked")
        #expect(thrown.withLock { $0 } is CancellationError)

        await clock.run()
        try await live.value
    }
}
