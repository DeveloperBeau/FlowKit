import Testing
import FlowCore
import FlowSharedModels
import FlowTesting
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
        let delivered = Mutex(0)
        let upstream = Flow<Int> { collector in
            for value in 1...3 {
                await collector.emit(value)
                await waitUntil { delivered.withLock { $0 } >= value }
            }
        }

        try await upstream.flatMapLatest { value -> Flow<String> in
            Flow<String> { collector in
                await collector.emit("from-\(value)")
            }
        }.test { tester in
            try await tester.expectValue("from-1", within: .seconds(5))
            delivered.withLock { $0 = 1 }
            try await tester.expectValue("from-2", within: .seconds(5))
            delivered.withLock { $0 = 2 }
            try await tester.expectValue("from-3", within: .seconds(5))
            delivered.withLock { $0 = 3 }
            try await tester.expectCompletion(within: .seconds(5))
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
        let cancelled = Mutex<[Int]>([])

        let upstream = MutableSharedFlow<Int>(replay: 0)

        // The scope timeout must sit above the waitUntil deadlines inside the
        // body (30s): if the scope cliff comes first, a loaded runner tears
        // down the collection mid-wait and the test fails as a flake instead
        // of converging.
        try await TestScope.run(timeout: .seconds(90)) { scope in
            // Observe cancellation by exiting the spin, not via
            // withTaskCancellationHandler: a cancel that races the handler's
            // registration can be missed by the runtime, whereas the
            // isCancelled flag is always visible to the spinning body.
            let resultFlow = upstream.asFlow().flatMapLatest { value -> Flow<String> in
                Flow<String> { collector in
                    // Simulate long work without occupying a pool thread.
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(1))
                    }
                    cancelled.withLock { $0.append(value) }
                }
            }

            _ = try await scope.test(resultFlow)

            // Wait until the subscriber count reaches 1 so we know the
            // tester has actually subscribed before we start emitting.
            await waitUntil { await upstream.subscriptionCount >= 1 }

            // Emit 1, 2, 3 in sequence; after each emit, poll until the
            // previous inner flow has observed its cancellation. Bounded
            // generously so a loaded runner converges but a genuine
            // regression still fails instead of hanging.
            func waitForCancellation(of value: Int) async {
                await waitUntil { cancelled.withLock { $0 }.contains(value) }
            }

            await upstream.emit(1)
            await upstream.emit(2)
            await waitForCancellation(of: 1)

            await upstream.emit(3)
            await waitForCancellation(of: 2)

            #expect(cancelled.withLock { $0 }.contains(1))
            #expect(cancelled.withLock { $0 }.contains(2))
        }
    }

    @Test("flatMapLatest on empty upstream produces empty flow")
    func emptyUpstream() async throws {
        let flow = Flow<Int>.empty
        try await flow.flatMapLatest { Flow(of: $0) }.test { tester in
            try await tester.expectCompletion()
        }
    }

    @Test("ThrowingFlow.flatMapLatest propagates inner errors")
    func throwingInnerError() async throws {
        struct SearchError: Error, Equatable {}
        let flow = ThrowingFlow(of: "query")
        try await flow.flatMapLatest { _ -> ThrowingFlow<String> in
            ThrowingFlow<String> { _ in throw SearchError() }
        }.test { tester in
            try await tester.expectError(SearchError())
        }
    }
}

@Suite("flatMapLatest cancellation propagation")
struct FlatMapLatestCancellationTests {
    @Test("cancelling the downstream collection cancels the active inner flow")
    func downstreamCancellationCancelsInner() async {
        let innerStarted = Mutex(false)
        let innerCancelled = Mutex(false)
        let upstream = MutableSharedFlow<Int>(replay: 0)

        let collector = Task {
            await upstream.asFlow().flatMapLatest { _ -> Flow<String> in
                Flow<String> { _ in
                    innerStarted.withLock { $0 = true }
                    // Long-running inner: exits only via cancellation, observed
                    // by polling isCancelled (never via onCancel handlers).
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(1))
                    }
                    innerCancelled.withLock { $0 = true }
                }
            }.collect { _ in }
        }
        await waitUntil { await upstream.subscriptionCount >= 1 }
        await upstream.emit(1)
        await waitUntil { innerStarted.withLock { $0 } }

        collector.cancel()
        await waitUntil { innerCancelled.withLock { $0 } }
        #expect(innerCancelled.withLock { $0 }, "downstream cancellation must reach the active inner flow")
        // The collection task itself must unwind instead of hanging in the
        // operator's completion wait. Guarded so a regression fails above
        // rather than hanging the suite here.
        if innerCancelled.withLock({ $0 }) { await collector.value }
    }

    @Test("ThrowingFlow: cancelling the downstream collection cancels the active inner flow")
    func throwingDownstreamCancellationCancelsInner() async {
        let innerStarted = Mutex(false)
        let innerCancelled = Mutex(false)
        // Emits once, then stays alive until cancelled, so the inner flow is
        // still active when the collection is torn down.
        let upstream = ThrowingFlow<Int> { collector in
            try await collector.emit(1)
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1))
            }
        }

        let collector = Task {
            try? await upstream.flatMapLatest { _ -> ThrowingFlow<String> in
                ThrowingFlow<String> { _ in
                    innerStarted.withLock { $0 = true }
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(1))
                    }
                    innerCancelled.withLock { $0 = true }
                }
            }.collect { _ in }
        }
        await waitUntil { innerStarted.withLock { $0 } }

        collector.cancel()
        await waitUntil { innerCancelled.withLock { $0 } }
        #expect(innerCancelled.withLock { $0 }, "downstream cancellation must reach the active inner flow")
        if innerCancelled.withLock({ $0 }) { await collector.value }
    }
}
