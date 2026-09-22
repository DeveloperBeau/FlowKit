import Testing
import FlowCore
import FlowTesting
@testable import FlowOperators

@Suite("transform operator")
struct TransformOperatorTests {
    @Test("transform can emit multiple values per upstream value")
    func fanOut() async throws {
        let flow = Flow(of: 1, 2, 3)
        try await flow.transform { value, collector in
            await collector.emit("\(value)a")
            await collector.emit("\(value)b")
        }.test { tester in
            try await tester.expectValue("1a")
            try await tester.expectValue("1b")
            try await tester.expectValue("2a")
            try await tester.expectValue("2b")
            try await tester.expectValue("3a")
            try await tester.expectValue("3b")
            try await tester.expectCompletion()
        }
    }

    @Test("transform can skip values by not emitting")
    func skip() async throws {
        let flow = Flow(of: 1, 2, 3, 4, 5)
        try await flow.transform { value, collector in
            if value.isMultiple(of: 2) {
                await collector.emit(value * 10)
            }
        }.test { tester in
            try await tester.expectValue(20)
            try await tester.expectValue(40)
            try await tester.expectCompletion()
        }
    }
}
