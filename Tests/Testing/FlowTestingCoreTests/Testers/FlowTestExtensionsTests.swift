import Testing
import Foundation
import FlowCore
import FlowSharedModels
import FlowTestClock
import FlowTestSupport
@testable import FlowTestingCore

@Suite("Flow.test extension")
struct FlowTestExtensionsTests {
    private struct BoomError: Error, Equatable {}

    @Test("Flow.test collects and exposes values via FlowTester")
    func flowTestCollectsValues() async throws {
        let flow = Flow(of: "one", "two", "three")
        try await flow.test(clock: TestClock()) { tester in
            try await tester.expectValue("one")
            try await tester.expectValue("two")
            try await tester.expectValue("three")
            try await tester.expectCompletion()
        }
    }

    @Test("ThrowingFlow.test exposes errors via ThrowingFlowTester")
    func throwingFlowTestExposesErrors() async throws {
        let flow = ThrowingFlow<Int> { collector in
            try await collector.emit(1)
            throw BoomError()
        }
        try await flow.test(clock: TestClock()) { tester in
            try await tester.expectValue(1)
            try await tester.expectError(BoomError())
        }
    }

    @Test("Flow.test throws FlowTestError.timeout when the clock reaches the deadline")
    func flowTestTimesOutAtTheDeadline() async throws {
        let clock = TestClock()
        let run = try await driveTimeout(on: clock, deadline: .seconds(10)) {
            try await Flow(of: 1).test(timeout: .seconds(10), clock: clock) { _ in
                await parkUntilCancelled()
            }
        }
        #expect(run.wasRunningBeforeDeadline, "the test timed out before the clock reached it")
        #expect(run.error as? FlowTestError == .timeout)
    }

    @Test("ThrowingFlow.test throws FlowTestError.timeout when the clock reaches the deadline")
    func throwingFlowTestTimesOutAtTheDeadline() async throws {
        let clock = TestClock()
        let run = try await driveTimeout(on: clock, deadline: .seconds(10)) {
            try await ThrowingFlow<Int> { _ in }.test(timeout: .seconds(10), clock: clock) { _ in
                await parkUntilCancelled()
            }
        }
        #expect(run.wasRunningBeforeDeadline, "the test timed out before the clock reached it")
        #expect(run.error as? FlowTestError == .timeout)
    }

    @Test("Flow.test propagates the block's error")
    func flowTestPropagatesBlockError() async {
        await #expect(throws: BoomError.self) {
            try await Flow(of: 1).test(clock: TestClock()) { _ in throw BoomError() }
        }
    }

    @Test("Flow.test cancels collection when the block exits")
    func flowTestCancelsCollection() async throws {
        let collecting = Signal()
        let cancelled = Signal()
        let flow = Flow<Int> { _ in
            collecting.fire()
            await parkUntilCancelled()
            cancelled.fire()
        }
        try await flow.test(clock: TestClock()) { _ in await collecting.wait() }
        await cancelled.wait()
        #expect(cancelled.hasFired)
    }

    @available(*, deprecated)
    @Test("The real-clock Flow.test and ThrowingFlow.test still collect")
    func legacyTestsCollect() async throws {
        try await Flow(of: "one").test(timeout: .seconds(3600)) { tester in
            try await tester.expectValue("one")
            try await tester.expectCompletion()
        }
        let failing = ThrowingFlow<Int> { collector in
            try await collector.emit(1)
            throw BoomError()
        }
        try await failing.test(timeout: .seconds(3600)) { tester in
            try await tester.expectValue(1)
            try await tester.expectError(BoomError())
        }
    }
}
