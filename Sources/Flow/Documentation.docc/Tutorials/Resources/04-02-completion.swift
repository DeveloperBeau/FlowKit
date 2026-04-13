import Testing
import Flow
import FlowTesting

@Suite("Flow basics")
struct FlowBasicsTests {

    @Test("Flow(of:) emits values then completes")
    func emitsValuesThenCompletes() async throws {
        try await Flow(of: "apple", "banana", "cherry").test { tester in
            try await tester.expectValue("apple")
            try await tester.expectValue("banana")
            try await tester.expectValue("cherry")
            // expectCompletion fails if a value arrives instead, or if
            // the stream hangs without completing within the timeout.
            try await tester.expectCompletion()
        }
    }
}
