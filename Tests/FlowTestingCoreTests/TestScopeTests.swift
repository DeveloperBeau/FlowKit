import Testing
import FlowCore
import FlowSharedModels
@testable import FlowTestingCore

@Suite("TestScope")
struct TestScopeTests {
    @Test("TestScope collects multiple flows concurrently")
    func multipleFlows() async throws {
        let flow1 = Flow(of: 1, 2, 3)
        let flow2 = Flow(of: "a", "b", "c")

        try await TestScope.run(timeout: .seconds(2)) { scope in
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

        try await TestScope.run(timeout: .seconds(2)) { scope in
            let t = try await scope.test(flow)
            try await t.expectValue(1)
            try await t.expectError(TestErr())
        }
    }
}
