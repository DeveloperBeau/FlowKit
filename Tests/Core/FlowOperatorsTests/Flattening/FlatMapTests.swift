import Testing
import FlowCore
import FlowSharedModels
import FlowTesting
@testable import FlowOperators

@Suite("flatMap operator")
struct FlatMapTests {
    @Test("flatMap collects each inner flow sequentially")
    func sequential() async throws {
        let flow = Flow(of: 1, 2, 3)
        try await flow.flatMap { value in
            Flow(of: value * 10, value * 100)
        }.test { tester in
            try await tester.expectValue(10)
            try await tester.expectValue(100)
            try await tester.expectValue(20)
            try await tester.expectValue(200)
            try await tester.expectValue(30)
            try await tester.expectValue(300)
            try await tester.expectCompletion()
        }
    }

    @Test("flatMap with empty inner flow skips")
    func emptyInner() async throws {
        let flow = Flow(of: 1, 2, 3)
        try await flow.flatMap { value -> Flow<Int> in
            if value == 2 { return .empty }
            return Flow(of: value)
        }.test { tester in
            try await tester.expectValue(1)
            try await tester.expectValue(3)
            try await tester.expectCompletion()
        }
    }

    @Test("flatMap on empty upstream produces empty flow")
    func emptyUpstream() async throws {
        let flow = Flow<Int>.empty
        try await flow.flatMap { Flow(of: $0) }.test { tester in
            try await tester.expectCompletion()
        }
    }

    @Test("ThrowingFlow.flatMap propagates inner errors")
    func throwingInnerError() async throws {
        struct InnerError: Error, Equatable {}
        let flow = ThrowingFlow(of: 1, 2)
        try await flow.flatMap { value -> ThrowingFlow<Int> in
            if value == 2 {
                return ThrowingFlow<Int> { _ in throw InnerError() }
            }
            return ThrowingFlow(of: value * 10)
        }.test { tester in
            try await tester.expectValue(10)
            try await tester.expectError(InnerError())
        }
    }

    @Test("flatMap with maxConcurrent limits parallel inner flows")
    func maxConcurrent() async throws {
        let activeConcurrent = Mutex(0)
        let maxObserved = Mutex(0)

        let flow = Flow(of: 1, 2, 3, 4, 5)
        try await flow.flatMap(maxConcurrent: 2) { value -> Flow<Int> in
            Flow<Int> { collector in
                activeConcurrent.withLock { $0 += 1 }
                maxObserved.withLock { $0 = max($0, activeConcurrent.withLock { $0 }) }
                try? await Task.sleep(for: .seconds(0.01)) // brief work
                await collector.emit(value * 10)
                activeConcurrent.withLock { $0 -= 1 }
            }
        }.test { tester in
            var received: [Int] = []
            for _ in 0..<5 {
                received.append(try await tester.awaitValue(within: .seconds(5)))
            }
            #expect(Set(received) == Set([10, 20, 30, 40, 50]))
            try await tester.expectCompletion(within: .seconds(5))
        }

        #expect(maxObserved.withLock { $0 } <= 2)
    }
}
