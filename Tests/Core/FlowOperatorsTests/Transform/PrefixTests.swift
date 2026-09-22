import Testing
import FlowCore
import FlowTesting
@testable import FlowOperators

@Suite("prefix operator")
struct PrefixTests {
    @Test("prefix takes the first N values then completes")
    func takesFirstN() async throws {
        let flow = Flow(of: 1, 2, 3, 4, 5)
        try await flow.prefix(3).test { tester in
            try await tester.expectValue(1)
            try await tester.expectValue(2)
            try await tester.expectValue(3)
            try await tester.expectCompletion()
        }
    }

    @Test("prefix zero produces empty flow")
    func prefixZero() async throws {
        let flow = Flow(of: 1, 2, 3)
        try await flow.prefix(0).test { tester in
            try await tester.expectCompletion()
        }
    }

    @Test("prefix N where N > count emits all values")
    func prefixMoreThanAvailable() async throws {
        let flow = Flow(of: 1, 2)
        try await flow.prefix(10).test { tester in
            try await tester.expectValue(1)
            try await tester.expectValue(2)
            try await tester.expectCompletion()
        }
    }
}
