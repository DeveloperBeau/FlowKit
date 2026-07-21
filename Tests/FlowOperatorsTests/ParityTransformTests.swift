import Testing
import FlowCore
import FlowSharedModels
import FlowTesting
import FlowOperators

@Suite("drop(while:) / prefix(while:)")
struct WhileOperatorTests {
    @Test("drop(while:) skips the matching prefix and keeps everything after")
    func dropWhileSkipsPrefix() async {
        let result = await Flow(of: 1, 2, 3, 4, 1).drop(while: { $0 < 3 }).toArray()
        #expect(result == [3, 4, 1])
    }

    @Test("drop(while:) on an always-matching predicate produces an empty flow")
    func dropWhileAll() async {
        let result = await Flow(of: 1, 2, 3).drop(while: { _ in true }).toArray()
        #expect(result == [])
    }

    @Test("prefix(while:) emits until the first failing value, ignoring the rest")
    func prefixWhileStopsAtFirstFailure() async {
        let result = await Flow(of: 1, 2, 3, 1).prefix(while: { $0 < 3 }).toArray()
        #expect(result == [1, 2])
    }

    @Test("prefix(while:) with an always-true predicate is identity")
    func prefixWhileIdentity() async {
        let result = await Flow(of: 1, 2, 3).prefix(while: { _ in true }).toArray()
        #expect(result == [1, 2, 3])
    }

    @Test("ThrowingFlow.drop(while:) propagates a predicate error")
    func throwingDropWhilePropagates() async throws {
        struct Bad: Error, Equatable {}
        let flow = ThrowingFlow(of: 1, 2).drop(while: { _ in throw Bad() })
        try await TestScope.run { scope in
            let tester = try await scope.test(flow)
            try await tester.expectError(Bad())
        }
    }

    @Test("ThrowingFlow.prefix(while:) propagates an upstream error")
    func throwingPrefixWhilePropagates() async throws {
        struct Bad: Error, Equatable {}
        let flow = ThrowingFlow<Int> { collector in
            try await collector.emit(1)
            throw Bad()
        }.prefix(while: { $0 < 10 })
        try await TestScope.run { scope in
            let tester = try await scope.test(flow)
            try await tester.expectValue(1)
            try await tester.expectError(Bad())
        }
    }
}

@Suite("enumerated operator")
struct EnumeratedTests {
    @Test("enumerated pairs each value with its zero-based offset")
    func enumeratesInOrder() async {
        let result = await Flow(of: "a", "b", "c").enumerated().toArray()
        #expect(result.map(\.offset) == [0, 1, 2])
        #expect(result.map(\.element) == ["a", "b", "c"])
    }

    @Test("enumerated on an empty flow emits nothing")
    func enumeratedEmpty() async {
        let result = await Flow<String>.empty.enumerated().toArray()
        #expect(result.isEmpty)
    }
}

@Suite("scan without initial value")
struct RunningScanTests {
    @Test("scan emits the first value unchanged then running accumulations")
    func runningAccumulation() async {
        let result = await Flow(of: 1, 2, 3, 4).scan { $0 + $1 }.toArray()
        #expect(result == [1, 3, 6, 10])
    }

    @Test("scan without initial on an empty flow emits nothing")
    func runningScanEmpty() async {
        let result = await Flow<Int>.empty.scan { $0 + $1 }.toArray()
        #expect(result == [])
    }

    @Test("ThrowingFlow.scan propagates an accumulator error")
    func runningScanPropagates() async throws {
        struct Bad: Error, Equatable {}
        let flow = ThrowingFlow(of: 1, 2).scan { _, _ in throw Bad() }
        try await TestScope.run { scope in
            let tester = try await scope.test(flow)
            try await tester.expectValue(1) // first value passes through untouched
            try await tester.expectError(Bad())
        }
    }
}

@Suite("chunks(ofCount:) operator")
struct ChunksTests {
    @Test("chunks groups values and emits the partial final chunk")
    func chunksWithRemainder() async {
        let result = await Flow(0..<7).chunks(ofCount: 3).toArray()
        #expect(result == [[0, 1, 2], [3, 4, 5], [6]])
    }

    @Test("chunks with an exact multiple emits no partial chunk")
    func chunksExact() async {
        let result = await Flow(0..<6).chunks(ofCount: 3).toArray()
        #expect(result == [[0, 1, 2], [3, 4, 5]])
    }

    @Test("chunks of count 1 wraps each value")
    func chunksOfOne() async {
        let result = await Flow(of: 9, 8).chunks(ofCount: 1).toArray()
        #expect(result == [[9], [8]])
    }

    @Test("chunks on an empty flow emits nothing")
    func chunksEmpty() async {
        let result = await Flow<Int>.empty.chunks(ofCount: 4).toArray()
        #expect(result.isEmpty)
    }

    @Test("a failing upstream discards the partial chunk and rethrows")
    func chunksErrorDiscardsPartial() async throws {
        struct Bad: Error, Equatable {}
        let flow = ThrowingFlow<Int> { collector in
            try await collector.emit(1)
            try await collector.emit(2)
            throw Bad()
        }.chunks(ofCount: 3)
        try await TestScope.run { scope in
            let tester = try await scope.test(flow)
            try await tester.expectError(Bad())
        }
    }

    @Test("10,000 values chunked by 7 flatten back to the original sequence")
    func chunksFuzz() async {
        let chunks = await Flow(0..<10_000).chunks(ofCount: 7).toArray()
        #expect(chunks.flatMap { $0 } == Array(0..<10_000))
        #expect(chunks.dropLast().allSatisfy { $0.count == 7 })
    }
}
