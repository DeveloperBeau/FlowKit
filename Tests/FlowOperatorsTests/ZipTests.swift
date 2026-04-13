import Testing
import FlowCore
import FlowTesting
@testable import FlowOperators

@Suite("zip operator")
struct ZipTests {
    @Test("zip pairs values from two flows positionally")
    func pairsPositionally() async throws {
        let flow1 = Flow(of: 1, 2, 3)
        let flow2 = Flow(of: "a", "b", "c")
        try await flow1.zip(flow2).test { tester in
            let v1 = try await tester.awaitValue()
            #expect(v1.0 == 1 && v1.1 == "a")
            let v2 = try await tester.awaitValue()
            #expect(v2.0 == 2 && v2.1 == "b")
            let v3 = try await tester.awaitValue()
            #expect(v3.0 == 3 && v3.1 == "c")
            try await tester.expectCompletion()
        }
    }

    @Test("zip completes when the shorter flow completes")
    func completesOnShorter() async throws {
        let flow1 = Flow(of: 1, 2, 3, 4, 5)
        let flow2 = Flow(of: "a", "b")
        try await flow1.zip(flow2).test { tester in
            _ = try await tester.awaitValue()
            _ = try await tester.awaitValue()
            try await tester.expectCompletion()
        }
    }

    @Test("zip with transform applies the closure to each pair")
    func withTransform() async throws {
        let flow1 = Flow(of: 1, 2, 3)
        let flow2 = Flow(of: 10, 20, 30)
        try await flow1.zip(flow2) { $0 + $1 }.test { tester in
            try await tester.expectValue(11)
            try await tester.expectValue(22)
            try await tester.expectValue(33)
            try await tester.expectCompletion()
        }
    }

    @Test("zip with empty flow produces empty flow")
    func emptyFlow() async throws {
        let flow1 = Flow(of: 1, 2, 3)
        let flow2 = Flow<String>.empty
        try await flow1.zip(flow2).test { tester in
            try await tester.expectCompletion()
        }
    }
}
