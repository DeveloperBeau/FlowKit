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

    @Test("FlowTester is reachable via .test(timeout:_:)")
    func flowTesterReachable() async throws {
        let flow = Flow(of: 1, 2, 3)
        try await flow.test { tester in
            try await tester.expectValue(1)
            try await tester.expectValue(2)
            try await tester.expectValue(3)
            try await tester.expectCompletion()
        }
    }

    @Test("ThrowingFlowTester is reachable via .test(timeout:_:)")
    func throwingTesterReachable() async throws {
        struct BoomError: Error, Equatable {}
        let flow = ThrowingFlow<Int> { _ in throw BoomError() }
        try await flow.test { tester in
            try await tester.expectError(BoomError())
        }
    }

    @Test("TestScope is reachable")
    func testScopeReachable() async throws {
        try await TestScope.run { scope in
            let t = try await scope.test(Flow(of: 42))
            try await t.expectValue(42)
        }
    }

    @Test("FlowTestError is reachable")
    func flowTestErrorReachable() {
        let error: FlowTestError = .timeout
        #expect(error == .timeout)
    }
}
