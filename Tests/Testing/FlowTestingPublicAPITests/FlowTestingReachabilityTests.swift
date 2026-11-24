import Testing
import Flow
import FlowTesting

@Suite("FlowTesting public API reachability")
struct FlowTestingReachabilityTests {
    @Test("TestClock is reachable and functional")
    func testClockReachable() async throws {
        let clock = TestClock()
        #expect(clock.now.offset == .zero)
        await clock.advance(by: .seconds(1))
        #expect(clock.now.offset == .seconds(1))
    }

    @Test("FlowTester is reachable via .test(clock:_:)")
    func flowTesterReachable() async throws {
        let flow = Flow(of: 1, 2, 3)
        try await flow.test(clock: TestClock()) { tester in
            try await tester.expectValue(1)
            try await tester.expectValue(2)
            try await tester.expectValue(3)
            try await tester.expectCompletion()
        }
    }

    @Test("ThrowingFlowTester is reachable via .test(clock:_:)")
    func throwingTesterReachable() async throws {
        struct BoomError: Error, Equatable {}
        let flow = ThrowingFlow<Int> { _ in throw BoomError() }
        try await flow.test(clock: TestClock()) { tester in
            try await tester.expectError(BoomError())
        }
    }

    @Test("FlowReader is reachable via .probing(_:)")
    func flowReaderReachable() async throws {
        try await Flow(of: 1, 2).probing { reader in
            try await reader.expectValue(1)
            try await reader.expectNextValue(2)
            try await reader.expectCompletion()
        }
        struct BoomError: Error {}
        try await ThrowingFlow<Int> { _ in throw BoomError() }.probing { reader in
            try await reader.expectError("boom") { $0 is BoomError }
        }
    }

    @Test("TestScope is reachable")
    func testScopeReachable() async throws {
        try await TestScope.run(clock: TestClock()) { scope in
            let t = try await scope.test(Flow(of: 42))
            try await t.expectValue(42)
        }
    }

    @Test("TestClock.waitForSleepers and FlowProbe.waitForValue are reachable")
    func pushWaitersReachable() async throws {
        let clock = TestClock()
        let sleeper = Task { try await clock.sleep(for: .seconds(1)) }
        let registered = Task { try await clock.waitForSleepers(1) }
        guard try await finishes(registered, "clock.waitForSleepers(1)") else {
            sleeper.cancel()
            return
        }
        await clock.advance(by: .seconds(1))
        guard try await finishes(sleeper, "the advanced sleeper") else { return }

        let probe = FlowProbe<Int>()
        await probe.record(3)
        let observed = Task { try await probe.waitForValue { $0 == 3 } }
        guard try await finishes(observed, "probe.waitForValue") else { return }
    }

    /// Awaits `task` under a wall-clock safety net. A task that never returns is
    /// cancelled and recorded as a named failure, and `false` tells the caller to
    /// stop rather than run later steps against a broken setup.
    private func finishes(_ task: Task<Void, any Error>, _ name: String) async throws -> Bool {
        do {
            try await withThrowingTimeout(.seconds(30)) {
                try await withTaskCancellationHandler {
                    try await task.value
                } onCancel: {
                    task.cancel()
                }
            }
            return true
        } catch FlowTestError.timeout {
            task.cancel()
            Issue.record("\(name) never returned")
            return false
        }
    }

    @Test("withThrowingTimeout and waitUntil accept a clock")
    func clockOverloadsReachable() async throws {
        let clock = TestClock()
        #expect(try await withThrowingTimeout(.seconds(1), clock: clock) { 5 } == 5)
        await waitUntil(clock: clock) { true }
    }

    @Test("FlowTestError is reachable")
    func flowTestErrorReachable() {
        let error: FlowTestError = .timeout
        #expect(error == .timeout)
    }
}
