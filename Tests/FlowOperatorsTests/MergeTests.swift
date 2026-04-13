import Testing
import FlowCore
import FlowHotStreams
import FlowTesting
@testable import FlowOperators

@Suite("merge operator")
struct MergeTests {
    @Test("merge interleaves values from multiple flows")
    func interleaves() async throws {
        let flow1 = Flow(of: 1, 2, 3)
        let flow2 = Flow(of: 10, 20, 30)
        try await Flow.merge(flow1, flow2).test { tester in
            var received: [Int] = []
            for _ in 0..<6 {
                received.append(try await tester.awaitValue())
            }
            // All values from both flows should be present
            #expect(Set(received) == Set([1, 2, 3, 10, 20, 30]))
            try await tester.expectCompletion()
        }
    }

    @Test("merge with single flow is identity")
    func singleFlow() async throws {
        let flow = Flow(of: "a", "b", "c")
        try await Flow.merge(flow).test { tester in
            try await tester.expectValue("a")
            try await tester.expectValue("b")
            try await tester.expectValue("c")
            try await tester.expectCompletion()
        }
    }

    @Test("merge completes when all flows complete")
    func completesWhenAllComplete() async throws {
        let flow1 = Flow(of: 1)
        let flow2 = Flow(of: 2)
        let flow3 = Flow(of: 3)
        try await Flow.merge(flow1, flow2, flow3).test { tester in
            var received: [Int] = []
            for _ in 0..<3 {
                received.append(try await tester.awaitValue())
            }
            #expect(Set(received) == Set([1, 2, 3]))
            try await tester.expectCompletion()
        }
    }

    @Test("merge with empty flows produces empty flow")
    func allEmpty() async throws {
        let flow1 = Flow<Int>.empty
        let flow2 = Flow<Int>.empty
        try await Flow.merge(flow1, flow2).test { tester in
            try await tester.expectCompletion()
        }
    }
}
