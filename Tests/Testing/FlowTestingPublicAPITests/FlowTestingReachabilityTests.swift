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
        try await clock.waitForSleepers(1)
        await clock.advance(by: .seconds(1))
        try await sleeper.value

        let probe = FlowProbe<Int>()
        await probe.record(3)
        try await probe.waitForValue { $0 == 3 }
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
