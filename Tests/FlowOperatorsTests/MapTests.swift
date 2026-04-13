import Testing
import FlowCore
import FlowTesting
@testable import FlowOperators

@Suite("map operator")
struct MapTests {
    @Test("map transforms each value")
    func mapTransforms() async throws {
        let flow = Flow(of: 1, 2, 3)
        try await flow.map { $0 * 10 }.test { tester in
            try await tester.expectValue(10)
            try await tester.expectValue(20)
            try await tester.expectValue(30)
            try await tester.expectCompletion()
        }
    }

    @Test("map with async transform supports suspension")
    func mapAsyncTransform() async throws {
        let flow = Flow(of: "alpha", "beta")
        try await flow.map { value -> String in
            await Task.yield()
            return value.uppercased()
        }.test { tester in
            try await tester.expectValue("ALPHA")
            try await tester.expectValue("BETA")
            try await tester.expectCompletion()
        }
    }

    @Test("map on empty flow produces empty flow")
    func mapEmpty() async throws {
        let flow = Flow<Int>.empty
        try await flow.map { $0 * 2 }.test { tester in
            try await tester.expectCompletion()
        }
    }
}
