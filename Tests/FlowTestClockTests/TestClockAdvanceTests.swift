import Testing
import Foundation
@testable import FlowTestClock

@Suite("TestClock advance")
struct TestClockAdvanceTests {
    @Test("now starts at zero offset")
    func nowStartsAtZero() {
        let clock = TestClock()
        #expect(clock.now.offset == .zero)
    }

    @Test("advance moves now forward")
    func advanceMovesNow() async {
        let clock = TestClock()
        await clock.advance(by: .seconds(5))
        #expect(clock.now.offset == .seconds(5))
    }

    @Test("sleep(until:) wakes when clock advances past deadline")
    func sleepWakesOnAdvance() async throws {
        let clock = TestClock()
        let wokeUp = NSLock()
        nonisolated(unsafe) var _wokeUp = false

        let task = Task {
            try await clock.sleep(until: TestClock.Instant(offset: .seconds(1)), tolerance: nil)
            wokeUp.withLock { _wokeUp = true }
        }

        try? await Task.sleep(nanoseconds: 10_000_000)
        let beforeAdvance = wokeUp.withLock { _wokeUp }
        #expect(!beforeAdvance)

        await clock.advance(by: .seconds(1))
        _ = try await task.value

        let afterAdvance = wokeUp.withLock { _wokeUp }
        #expect(afterAdvance)
    }

    @Test("multiple sleepers wake in deadline order via incremental advance")
    func multipleSleepers() async throws {
        let clock = TestClock()
        let orderLock = NSLock()
        nonisolated(unsafe) var _wakeOrder: [Int] = []

        let t1 = Task {
            try await clock.sleep(until: TestClock.Instant(offset: .seconds(2)), tolerance: nil)
            orderLock.withLock { _wakeOrder.append(2) }
        }

        let t2 = Task {
            try await clock.sleep(until: TestClock.Instant(offset: .seconds(1)), tolerance: nil)
            orderLock.withLock { _wakeOrder.append(1) }
        }

        let t3 = Task {
            try await clock.sleep(until: TestClock.Instant(offset: .seconds(3)), tolerance: nil)
            orderLock.withLock { _wakeOrder.append(3) }
        }

        // Give all sleepers time to register
        try? await Task.sleep(nanoseconds: 20_000_000)

        // Advance incrementally so each sleeper wakes and appends before
        // the next one is resumed.
        await clock.advance(by: .seconds(1))
        try await t2.value
        await clock.advance(by: .seconds(1))
        try await t1.value
        await clock.advance(by: .seconds(1))
        try await t3.value

        let order = orderLock.withLock { _wakeOrder }
        #expect(order == [1, 2, 3])
    }

    @Test("cancelled sleep throws CancellationError")
    func cancelledSleepThrows() async throws {
        let clock = TestClock()
        let task = Task {
            try await clock.sleep(until: TestClock.Instant(offset: .seconds(10)), tolerance: nil)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
        task.cancel()
        do {
            try await task.value
            Issue.record("expected CancellationError")
        } catch is CancellationError {
            // expected
        } catch {
            Issue.record("expected CancellationError, got \(error)")
        }
    }

    @Test("sleep with already-passed deadline returns immediately")
    func sleepPastDeadline() async throws {
        let clock = TestClock()
        await clock.advance(by: .seconds(10))
        // Deadline is in the past. Should return immediately.
        try await clock.sleep(until: TestClock.Instant(offset: .seconds(5)), tolerance: nil)
        // If we reach here without hanging, the test passes.
    }

    @Test("advance by zero duration is a no-op")
    func advanceByZero() async {
        let clock = TestClock()
        await clock.advance(by: .zero)
        #expect(clock.now.offset == .zero)
    }
}
