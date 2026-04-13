import Testing
import FlowCore
import FlowTesting
@testable import FlowOperators

@Suite("removeDuplicates operator")
struct RemoveDuplicatesTests {
    @Test("removeDuplicates drops consecutive equal values")
    func dropsConsecutive() async throws {
        let flow = Flow(of: 1, 1, 2, 2, 2, 3, 1, 1)
        try await flow.removeDuplicates().test { tester in
            try await tester.expectValue(1)
            try await tester.expectValue(2)
            try await tester.expectValue(3)
            try await tester.expectValue(1) // 1 again after 3 — not consecutive duplicate
            try await tester.expectCompletion()
        }
    }

    @Test("removeDuplicates by predicate uses custom comparison")
    func byPredicate() async throws {
        let flow = Flow(of: "Hello", "HELLO", "World", "world")
        try await flow.removeDuplicates(by: { $0.lowercased() == $1.lowercased() }).test { tester in
            try await tester.expectValue("Hello")
            try await tester.expectValue("World")
            try await tester.expectCompletion()
        }
    }

    @Test("removeDuplicates on empty flow produces empty flow")
    func emptyFlow() async throws {
        let flow = Flow<Int>.empty
        try await flow.removeDuplicates().test { tester in
            try await tester.expectCompletion()
        }
    }

    @Test("removeDuplicates on all-unique flow passes all through")
    func allUnique() async throws {
        let flow = Flow(of: 1, 2, 3, 4, 5)
        try await flow.removeDuplicates().test { tester in
            for i in 1...5 {
                try await tester.expectValue(i)
            }
            try await tester.expectCompletion()
        }
    }
}
