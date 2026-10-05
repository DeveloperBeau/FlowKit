import Testing
import Foundation
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
        try await clock.waitForSleepers(1)
        try await clock.waitForSleepers(2)
        await clock.run()
        try await first.value
        try await second.value
    }

    @Test("A count of zero or less returns with no sleepers")
    func zeroReturnsImmediately() async throws {
        let clock = TestClock()
        try await clock.waitForSleepers(0)
        try await clock.waitForSleepers(-1)
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
}
