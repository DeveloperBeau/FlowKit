import Testing
import Foundation
import FlowCore
import FlowSharedModels
@testable import FlowTestingCore

@Suite("Flow.test extension")
struct FlowTestExtensionsTests {
    @Test("Flow.test collects and exposes values via FlowTester")
    func flowTestCollectsValues() async throws {
        let flow = Flow(of: "one", "two", "three")
        try await flow.test(timeout: .seconds(15)) { tester in
            try await tester.expectValue("one")
            try await tester.expectValue("two")
            try await tester.expectValue("three")
            try await tester.expectCompletion()
        }
    }

    @Test("ThrowingFlow.test exposes errors via ThrowingFlowTester")
    func throwingFlowTestExposesErrors() async throws {
        struct BoomError: Error, Equatable {}
        let flow = ThrowingFlow<Int> { collector in
            try await collector.emit(1)
            throw BoomError()
        }
        try await flow.test(timeout: .seconds(15)) { tester in
            try await tester.expectValue(1)
            try await tester.expectError(BoomError())
        }
    }
}
