import Testing
import FlowCore
import FlowTesting
@testable import FlowOperators

@Suite("dropFirst operator")
struct DropFirstTests {
    @Test("dropFirst skips the first N values")
    func skipsFirstN() async throws {
        let flow = Flow(of: 1, 2, 3, 4, 5)
        try await flow.dropFirst(2).test { tester in
            try await tester.expectValue(3)
            try await tester.expectValue(4)
            try await tester.expectValue(5)
            try await tester.expectCompletion()
        }
    }

    @Test("dropFirst zero is identity")
    func dropZero() async throws {
        let flow = Flow(of: 10, 20, 30)
        try await flow.dropFirst(0).test { tester in
            try await tester.expectValue(10)
            try await tester.expectValue(20)
            try await tester.expectValue(30)
            try await tester.expectCompletion()
        }
    }

    @Test("dropFirst N where N > count produces empty flow")
    func dropMoreThanAvailable() async throws {
        let flow = Flow(of: 1, 2)
        try await flow.dropFirst(5).test { tester in
            try await tester.expectCompletion()
        }
    }
}
