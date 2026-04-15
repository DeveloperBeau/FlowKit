import Testing
import FlowCore
import FlowTesting
@testable import FlowOperators

@Suite("scan operator")
struct ScanTests {
    @Test("scan emits running accumulations")
    func runningSum() async throws {
        let flow = Flow(of: 1, 2, 3, 4)
        try await flow.scan(0) { $0 + $1 }.test { tester in
            try await tester.expectValue(1)
            try await tester.expectValue(3)
            try await tester.expectValue(6)
            try await tester.expectValue(10)
            try await tester.expectCompletion()
        }
    }

    @Test("scan on empty flow emits nothing")
    func scanEmpty() async throws {
        let flow = Flow<Int>.empty
        try await flow.scan(0) { $0 + $1 }.test { tester in
            try await tester.expectCompletion()
        }
    }

    @Test("scan accumulates strings")
    func scanStrings() async throws {
        let flow = Flow(of: "a", "b", "c")
        try await flow.scan("") { acc, value in acc + value }.test { tester in
            try await tester.expectValue("a")
            try await tester.expectValue("ab")
            try await tester.expectValue("abc")
            try await tester.expectCompletion()
        }
    }
}
