import Testing
import FlowCore
import FlowHotStreams
import FlowTesting
@testable import FlowOperators

@Suite("ThrowingFlow combining operators")
struct ThrowingFlowCombiningTests {
    // MARK: - zip

    @Test("ThrowingFlow.zip pairs values positionally")
    func zipPairs() async throws {
        let flow1 = ThrowingFlow(of: 1, 2, 3)
        let flow2 = ThrowingFlow(of: "a", "b", "c")
        try await flow1.zip(flow2).test { tester in
            let v1 = try await tester.awaitValue()
            #expect(v1.0 == 1 && v1.1 == "a")
            let v2 = try await tester.awaitValue()
            #expect(v2.0 == 2 && v2.1 == "b")
            let v3 = try await tester.awaitValue()
            #expect(v3.0 == 3 && v3.1 == "c")
            try await tester.expectCompletion()
        }
    }

    @Test("ThrowingFlow.zip propagates errors from either side")
    func zipPropagatesError() async throws {
        struct ZipError: Error, Equatable {}
        let flow1 = ThrowingFlow<Int> { collector in
            try await collector.emit(1)
            throw ZipError()
        }
        let flow2 = ThrowingFlow(of: "a", "b", "c")
        try await flow1.zip(flow2).test { tester in
            _ = try await tester.awaitValue()
            try await tester.expectError(ZipError())
        }
    }

    // MARK: - combineLatest

    @Test("ThrowingFlow.combineLatest emits latest pairs")
    func combineLatestPairs() async throws {
        let flow1 = ThrowingFlow(of: 1, 2)
        let flow2 = ThrowingFlow(of: 10, 20)
        try await flow1.combineLatest(flow2).test { tester in
            let first = try await tester.awaitValue()
            #expect(first.0 >= 1 && first.1 >= 10)
        }
    }

    @Test("ThrowingFlow.combineLatest propagates errors")
    func combineLatestPropagatesError() async throws {
        struct CombineError: Error, Equatable {}
        let flow1 = ThrowingFlow<Int> { _ in throw CombineError() }
        let flow2 = ThrowingFlow(of: 1, 2, 3)
        try await flow1.combineLatest(flow2).test { tester in
            try await tester.expectError(CombineError())
        }
    }

    // MARK: - merge

    @Test("ThrowingFlow.merge interleaves values")
    func mergeInterleaves() async throws {
        let flow1 = ThrowingFlow(of: 1, 2, 3)
        let flow2 = ThrowingFlow(of: 10, 20, 30)
        try await ThrowingFlow.merge(flow1, flow2).test { tester in
            var received: [Int] = []
            for _ in 0..<6 {
                received.append(try await tester.awaitValue())
            }
            #expect(Set(received) == Set([1, 2, 3, 10, 20, 30]))
            try await tester.expectCompletion()
        }
    }

    @Test("ThrowingFlow.merge propagates errors from any flow")
    func mergePropagatesError() async throws {
        struct MergeError: Error, Equatable {}
        let flow1 = ThrowingFlow<Int> { collector in
            try await collector.emit(1)
            throw MergeError()
        }
        let flow2 = ThrowingFlow<Int> { _ in
            // Never emits. Just waits so merge stays alive until error fires.
        }
        try await ThrowingFlow.merge(flow1, flow2).test { tester in
            _ = try await tester.awaitValue()  // the 1 from flow1
            try await tester.expectError(MergeError())
        }
    }

    @Test("ThrowingFlow.merge with array completes when all complete")
    func mergeArrayCompletes() async throws {
        let flows: [ThrowingFlow<Int>] = [ThrowingFlow(of: 1), ThrowingFlow(of: 2)]
        try await ThrowingFlow.merge(flows).test { tester in
            var received: [Int] = []
            for _ in 0..<2 {
                received.append(try await tester.awaitValue())
            }
            #expect(Set(received) == Set([1, 2]))
            try await tester.expectCompletion()
        }
    }
}
