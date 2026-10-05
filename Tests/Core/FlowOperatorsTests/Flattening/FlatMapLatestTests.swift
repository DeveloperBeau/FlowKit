import Testing
import FlowCore
import FlowSharedModels
import FlowTesting
import FlowTestSupport
@testable import FlowOperators
@testable import FlowHotStreams

@Suite("flatMapLatest operator")
struct FlatMapLatestTests {
    @Test("a paced upstream delivers every inner's value in order, then completes")
    func pacedUpstreamDeliversAll() async throws {
        // The upstream emits the next value only after the previous inner's
        // output was observed downstream, so every inner gets to complete
        // before it would be superseded. This is deterministic under load,
        // unlike a free-running upstream, where flatMapLatest may legitimately
        // skip intermediate inners (see fastUpstreamKeepsLatest).
        let delivered = Recorder<Void>()
        let upstream = Flow<Int> { collector in
            for value in 1...3 {
                await collector.emit(value)
                await delivered.wait(atLeast: value)
            }
        }

        try await upstream.flatMapLatest { value -> Flow<String> in
            Flow<String> { collector in
                await collector.emit("from-\(value)")
            }
        }.probing { tester in
            try await tester.expectValue("from-1")
            delivered.record(())
            try await tester.expectValue("from-2")
            delivered.record(())
            try await tester.expectValue("from-3")
            delivered.record(())
            try await tester.expectCompletion()
        }
    }

    @Test("a fast upstream may skip intermediate inners but always delivers the final one, in order")
    func fastUpstreamKeepsLatest() async {
        // Kotlin parity: with a free-running upstream, each new value cancels
        // the previous inner, so intermediates may never emit. What IS
        // guaranteed: the observed values are an in-order subsequence of the
        // inners' outputs, and the final inner runs to completion.
        let values = await Flow(of: 1, 2, 3).flatMapLatest { value -> Flow<String> in
            Flow(of: "from-\(value)")
        }.toArray()

        let allInOrder = ["from-1", "from-2", "from-3"]
        #expect(values.last == "from-3", "the final inner must always deliver")
        var remainder = allInOrder[...]
        let isSubsequence = values.allSatisfy { value in
            guard let index = remainder.firstIndex(of: value) else { return false }
            remainder = remainder[(index + 1)...]
            return true
        }
        #expect(isSubsequence, "\(values) must be an in-order subsequence of \(allInOrder)")
    }

    @Test("a superseded inner never delivers after its replacement (generation order)")
    func generationOrderUnderRacingUpstream() async {
        // A free-running upstream races 20 inner flows, each emitting a burst.
        // Whatever subset survives, the observed generations must be
        // monotonic, and the final inner's full burst must arrive last.
        for _ in 0..<20 {
            let upstreamCount = 20
            let burst = 5
            let values = await Flow(1...upstreamCount).flatMapLatest { generation -> Flow<Int> in
                Flow<Int> { collector in
                    for sequence in 0..<burst {
                        await collector.emit(generation * 1000 + sequence)
                    }
                }
            }.toArray()

            let generations = values.map { $0 / 1000 }
            #expect(
                zip(generations, generations.dropFirst()).allSatisfy { $0 <= $1 },
                "a superseded inner delivered after its replacement: \(values)"
            )
            let expectedTail = (0..<burst).map { upstreamCount * 1000 + $0 }
            #expect(
                Array(values.suffix(burst)) == expectedTail,
                "the final inner must run to completion: \(values.suffix(burst))"
            )
        }
    }

    @Test("flatMapLatest cancels long-running inner when new value arrives")
    func cancelsLongRunning() async throws {
        let cancelled = Recorder<Int>()

        let upstream = MutableSharedFlow<Int>(replay: 0)

        try await ProbeScope.run { scope in
            let resultFlow = upstream.asFlow().flatMapLatest { value -> Flow<String> in
                Flow<String> { collector in
                    // Simulate long work without occupying a pool thread.
                    await parkUntilCancelled()
                    cancelled.record(value)
                }
            }

            _ = scope.probe(resultFlow)

            // Wait until the subscriber count reaches 1 so we know the
            // tester has actually subscribed before we start emitting.
            try await upstream.waitForSubscribers(1)

            // Emit 1, 2, 3 in sequence; after each emit, wait until the
            // previous inner flow has observed its cancellation.
            func waitForCancellation(of value: Int) async {
                await cancelled.wait { $0.contains(value) }
            }

            await upstream.emit(1)
            await upstream.emit(2)
            await waitForCancellation(of: 1)

            await upstream.emit(3)
            await waitForCancellation(of: 2)

            #expect(cancelled.elements.contains(1))
            #expect(cancelled.elements.contains(2))
        }
    }

    @Test("flatMapLatest on empty upstream produces empty flow")
    func emptyUpstream() async throws {
        let flow = Flow<Int>.empty
        try await flow.flatMapLatest { Flow(of: $0) }.probing { tester in
            try await tester.expectCompletion()
        }
    }

    @Test("ThrowingFlow.flatMapLatest propagates inner errors")
    func throwingInnerError() async throws {
        struct SearchError: Error, Equatable {}
        let flow = ThrowingFlow(of: "query")
        try await flow.flatMapLatest { _ -> ThrowingFlow<String> in
            ThrowingFlow<String> { _ in throw SearchError() }
        }.probing { tester in
            try await tester.expectError(SearchError())
        }
    }
}

@Suite("flatMapLatest cancellation propagation")
struct FlatMapLatestCancellationTests {
    @Test("cancelling the downstream collection cancels the active inner flow")
    func downstreamCancellationCancelsInner() async throws {
        let innerStarted = Signal()
        let innerCancelled = Signal()
        let upstream = MutableSharedFlow<Int>(replay: 0)

        let collector = Task {
            await upstream.asFlow().flatMapLatest { _ -> Flow<String> in
                Flow<String> { _ in
                    innerStarted.fire()
                    // Long-running inner: exits only via cancellation, observed
                    // by polling isCancelled (never via onCancel handlers).
                    await parkUntilCancelled()
                    innerCancelled.fire()
                }
            }.collect { _ in }
        }
        try await upstream.waitForSubscribers(1)
        await upstream.emit(1)
        await innerStarted.wait()

        collector.cancel()
        await innerCancelled.wait()
        #expect(innerCancelled.hasFired, "downstream cancellation must reach the active inner flow")
        // The collection task itself must unwind instead of hanging in the
        // operator's completion wait. Guarded so a regression fails above
        // rather than hanging the suite here.
        if innerCancelled.hasFired { await collector.value }
    }

    @Test("ThrowingFlow: cancelling the downstream collection cancels the active inner flow")
    func throwingDownstreamCancellationCancelsInner() async {
        let innerStarted = Signal()
        let innerCancelled = Signal()
        // Emits once, then stays alive until cancelled, so the inner flow is
        // still active when the collection is torn down.
        let upstream = ThrowingFlow<Int> { collector in
            try await collector.emit(1)
            await parkUntilCancelled()
        }

        let collector = Task {
            try? await upstream.flatMapLatest { _ -> ThrowingFlow<String> in
                ThrowingFlow<String> { _ in
                    innerStarted.fire()
                    await parkUntilCancelled()
                    innerCancelled.fire()
                }
            }.collect { _ in }
        }
        await innerStarted.wait()

        collector.cancel()
        await innerCancelled.wait()
        #expect(innerCancelled.hasFired, "downstream cancellation must reach the active inner flow")
        if innerCancelled.hasFired { await collector.value }
    }
}
