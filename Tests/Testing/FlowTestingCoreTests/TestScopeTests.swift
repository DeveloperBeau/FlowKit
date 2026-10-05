import Testing
import FlowCore
import FlowSharedModels
import FlowTestClock
import FlowTestSupport
@testable import FlowTestingCore

@Suite("TestScope")
struct TestScopeTests {
    @Test("TestScope collects multiple flows concurrently")
    func multipleFlows() async throws {
        let flow1 = Flow(of: 1, 2, 3)
        let flow2 = Flow(of: "a", "b", "c")

        try await TestScope.run(clock: TestClock()) { scope in
            let t1 = try await scope.test(flow1)
            let t2 = try await scope.test(flow2)

            try await t1.expectValue(1)
            try await t2.expectValue("a")
            try await t1.expectValue(2)
            try await t2.expectValue("b")
            try await t1.expectValue(3)
            try await t2.expectValue("c")
            try await t1.expectCompletion()
            try await t2.expectCompletion()
        }
    }

    @Test("TestScope works with ThrowingFlow")
    func throwingFlowInScope() async throws {
        struct TestErr: Error, Equatable {}
        let flow = ThrowingFlow<Int> { collector in
            try await collector.emit(1)
            throw TestErr()
        }

        try await TestScope.run(clock: TestClock()) { scope in
            let t = try await scope.test(flow)
            try await t.expectValue(1)
            try await t.expectError(TestErr())
        }
    }

    @Test("TestScope.run throws FlowTestError.timeout when the clock reaches the deadline")
    func timeoutAtTheDeadline() async throws {
        let clock = TestClock()
        let run = try await driveTimeout(on: clock, deadline: .seconds(10)) {
            try await TestScope.run(timeout: .seconds(10), clock: clock) { _ in
                await parkUntilCancelled()
            }
        }
        #expect(run.wasRunningBeforeDeadline, "the scope timed out before the clock reached it")
        #expect(run.error as? FlowTestError == .timeout)
    }

    @Test("TestScope.run propagates the block's error")
    func blockErrorPropagates() async {
        struct BlockError: Error, Equatable {}
        await #expect(throws: BlockError.self) {
            try await TestScope.run(clock: TestClock()) { _ in throw BlockError() }
        }
    }

    @Test("TestScope.run cancels the collection of its flows when the block exits")
    func collectionEndsWithTheBlock() async throws {
        let collecting = Signal()
        let cancelled = Signal()
        let flow = Flow<Int> { _ in
            collecting.fire()
            await parkUntilCancelled()
            cancelled.fire()
        }
        try await TestScope.run(clock: TestClock()) { scope in
            _ = try await scope.test(flow)
            await collecting.wait()
        }
        await cancelled.wait()
        #expect(cancelled.hasFired)
    }

    @available(*, deprecated)
    @Test("The real-clock TestScope.run still collects flows")
    func legacyRunCollects() async throws {
        let flow = Flow(of: 1, 2)
        try await TestScope.run(timeout: .seconds(3600)) { scope in
            let tester = try await scope.test(flow)
            try await tester.expectValue(1)
            try await tester.expectValue(2)
            try await tester.expectCompletion()
        }
    }
}
