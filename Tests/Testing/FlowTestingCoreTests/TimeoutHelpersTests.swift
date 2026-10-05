import Testing
import Foundation
import FlowSharedModels
import FlowTestClock
import FlowTestSupport
@testable import FlowTestingCore

@Suite("TimeoutHelpers")
struct TimeoutHelpersTests {
    private struct BodyError: Error, Equatable {}

    @Test("withThrowingTimeout returns the body's value without advancing the clock")
    func successReturnsValue() async throws {
        let clock = TestClock()
        let result = try await withThrowingTimeout(.seconds(5), clock: clock) { 42 }
        #expect(result == 42)
        #expect(clock.now.offset == .zero)
    }

    @Test("withThrowingTimeout throws FlowTestError.timeout when the clock reaches the deadline")
    func timeoutThrowsAtTheDeadline() async throws {
        let clock = TestClock()
        let run = try await driveTimeout(on: clock, deadline: .seconds(5)) {
            _ = try await withThrowingTimeout(.seconds(5), clock: clock) {
                await parkUntilCancelled()
                return 0
            }
        }
        #expect(run.wasRunningBeforeDeadline, "the timeout fired before the clock reached it")
        #expect(run.error as? FlowTestError == .timeout)
    }

    @Test("withThrowingTimeout does not scale a custom clock's deadline")
    func customClockIsNotScaled() async throws {
        // The deadline is exactly `duration` on the supplied clock, whatever
        // FLOWKIT_TIMEOUT_SCALE the runner sets.
        let clock = TestClock()
        let run = try await driveTimeout(on: clock, deadline: .seconds(1)) {
            _ = try await withThrowingTimeout(.seconds(1), clock: clock) {
                await parkUntilCancelled()
                return 0
            }
        }
        #expect(run.error as? FlowTestError == .timeout)
    }

    @Test("withThrowingTimeout propagates body errors")
    func propagatesBodyErrors() async throws {
        let clock = TestClock()
        await #expect(throws: BodyError.self) {
            _ = try await withThrowingTimeout(.seconds(5), clock: clock) { throw BodyError() }
        }
    }

    @Test("withThrowingTimeout cancels its timer when the body finishes first")
    func successCancelsTheTimer() async throws {
        let clock = TestClock()
        _ = try await withThrowingTimeout(.seconds(5), clock: clock) { 1 }
        #expect(clock.sleeperCount == 0, "the timer sleep outlived the call")
    }

    @Test("withThrowingTimeout cancels the body when the deadline passes")
    func timeoutCancelsTheBody() async throws {
        let clock = TestClock()
        let bodyCancelled = Signal()
        let run = try await driveTimeout(on: clock, deadline: .seconds(5)) {
            _ = try await withThrowingTimeout(.seconds(5), clock: clock) {
                await parkUntilCancelled()
                bodyCancelled.fire()
                return 0
            }
        }
        #expect(run.error as? FlowTestError == .timeout)
        #expect(bodyCancelled.hasFired)
    }

    // The real-clock overload, kept as a deliberate real-time path. A body that
    // never finishes loses to any positive timeout, so the outcome cannot flake.
    @Test("withThrowingTimeout without a clock uses the real clock")
    func defaultClockTimesOut() async {
        await #expect(throws: FlowTestError.self) {
            _ = try await withThrowingTimeout(.milliseconds(1)) {
                await parkUntilCancelled()
                return 0
            }
        }
        let value = try? await withThrowingTimeout(.seconds(3600)) { 7 }
        #expect(value == 7)
    }
}
