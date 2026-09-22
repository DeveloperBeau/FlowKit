import Testing
import FlowCore
import FlowTesting
@testable import FlowOperators

@Suite("compactMap operator")
struct CompactMapTests {
    @Test("compactMap drops nil values and emits non-nil")
    func compactMapDropsNil() async throws {
        let flow = Flow(of: "1", "two", "3", "four", "5")
        try await flow.compactMap { Int($0) }.test { tester in
            try await tester.expectValue(1)
            try await tester.expectValue(3)
            try await tester.expectValue(5)
            try await tester.expectCompletion()
        }
    }

    @Test("compactMap with all nil produces empty flow")
    func allNil() async throws {
        let flow = Flow(of: "a", "b", "c")
        try await flow.compactMap { _ -> Int? in nil }.test { tester in
            try await tester.expectCompletion()
        }
    }
}
