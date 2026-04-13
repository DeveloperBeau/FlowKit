import Testing
import Flow
import FlowTesting

@Suite("Flow basics")
struct FlowBasicsTests {

    @Test("Flow(of:) emits values in order")
    func emitsValuesInOrder() async throws {
        // Flow(of:) is a simple cold source — it emits every argument
        // and then completes. Great for testing downstream operators in isolation.
        try await Flow(of: "apple", "banana", "cherry").test { tester in
            try await tester.expectValue("apple")
            try await tester.expectValue("banana")
            try await tester.expectValue("cherry")
        }
    }
}
