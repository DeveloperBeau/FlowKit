import Testing
import Flow
import FlowTesting

@Suite("Flow basics")
struct FlowBasicsTests {

    @Test("Flow(of:) emits values then completes")
    func emitsValuesThenCompletes() async throws {
        try await Flow(of: "apple", "banana", "cherry").probing { reader in
            try await reader.expectValue("apple")
            try await reader.expectValue("banana")
            try await reader.expectValue("cherry")
            // expectCompletion fails if a value arrives instead of the
            // completion. It waits for the flow itself, with no timeout.
            try await reader.expectCompletion()
        }
    }
}
