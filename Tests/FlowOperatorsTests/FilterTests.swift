import Testing
import FlowCore
import FlowTesting
@testable import FlowOperators

@Suite("filter operator")
struct FilterTests {
    @Test("filter emits only matching values")
    func filterEmitsMatching() async throws {
        let flow = Flow(of: 1, 2, 3, 4, 5, 6)
        try await flow.filter { $0.isMultiple(of: 2) }.test { tester in
            try await tester.expectValue(2)
            try await tester.expectValue(4)
            try await tester.expectValue(6)
            try await tester.expectCompletion()
        }
    }

    @Test("filter with all-false predicate produces empty flow")
    func allFiltered() async throws {
        let flow = Flow(of: 1, 2, 3)
        try await flow.filter { _ in false }.test { tester in
            try await tester.expectCompletion()
        }
    }
}
