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
            try await withThrowingTimeout(.seconds(5)) { try await upstream.waitForSubscribers(1) }

            // Emit 1, 2, 3 in sequence; after each emit, wait until the
            // previous inner flow has observed its cancellation.
            func waitForCancellation(of value: Int) async throws {
                try await withThrowingTimeout(.seconds(5)) {
                    await cancelled.wait { $0.contains(value) }
                }
            }

            await upstream.emit(1)
            await upstream.emit(2)
            try await waitForCancellation(of: 1)

            await upstream.emit(3)
            try await waitForCancellation(of: 2)

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

    // MARK: - Inner failure with an upstream that never completes (issue 80)

    @Test("an inner failure with an open upstream ends the flow, so catch runs")
    func innerFailureWithOpenUpstreamRunsCatch() async throws {
        let state = MutableStateFlow("a")
        let flow = state.asFlow()
            .mapThrowing { $0 }
            .flatMapLatest { _ -> ThrowingFlow<String> in
                ThrowingFlow<String> { _ in throw Boom() }
            }
            .catch { _, collector in await collector.emit("caught") }

        let result = try await withThrowingTimeout(.seconds(5)) {
            await flow.first()
        }
        #expect(result == "caught")
    }

    @Test("an inner failure with an open upstream throws the error and releases the upstream")
    func innerFailureWithOpenUpstreamThrowsAndReleasesUpstream() async throws {
        let state = MutableStateFlow("a")
        let flow = state.asFlow()
            .mapThrowing { $0 }
            .flatMapLatest { _ -> ThrowingFlow<String> in
                ThrowingFlow<String> { _ in throw Boom() }
            }

        let thrown = try await withThrowingTimeout(.seconds(5)) {
            await failure(of: flow, recording: Recorder<String>())
        }
        #expect(thrown is Boom, "expected Boom, got \(String(describing: thrown))")

        // The upstream collector must be cancelled, not left attached.
        try await withThrowingTimeout(.seconds(5)) {
            try await state.waitForSubscribers(atMost: 0)
        }
    }

    @Test("an inner that completes normally does not end the flow while the upstream is open")
    func innerCompletionWithOpenUpstreamKeepsFlowing() async throws {
        let state = MutableStateFlow("a")
        let flow = state.asFlow()
            .mapThrowing { $0 }
            .flatMapLatest { value -> ThrowingFlow<String> in
                ThrowingFlow(of: "result-\(value)")
            }

        try await withThrowingTimeout(.seconds(5)) {
            try await flow.probing { tester in
                try await tester.expectValue("result-a")
                state.send("b")
                try await tester.expectValue("result-b")
            }
        }
    }

    @Test("an inner that fails while it is running is torn down along with the upstream")
    func innerFailureCancelsRunningInner() async throws {
        // flatMapLatest keeps one inner live at a time: a new upstream value
        // cancels the previous inner before the next one starts. So the inner
        // that is running when the failure happens is the one that fails.
        // Here that inner is genuinely live, subscribed to its own source that
        // never completes, and it has already emitted. It then fails on a later
        // value from that source, while the upstream stays open.
        let upstream = MutableStateFlow("a")
        let innerSource = MutableStateFlow("x")
        let flow = upstream.asFlow()
            .mapThrowing { $0 }
            .flatMapLatest { outer -> ThrowingFlow<String> in
                innerSource.asFlow().mapThrowing { inner in
                    if inner == "boom" { throw Boom() }
                    return "\(outer)-\(inner)"
                }
            }
        let values = Recorder<String>()

        let thrown = try await withThrowingTimeout(.seconds(5)) { () async throws -> (any Error)? in
            async let outcome = failure(of: flow, recording: values)
            // The inner is running: it has emitted and is still attached.
            await values.wait(atLeast: 1)
            try await innerSource.waitForSubscribers(1)
            innerSource.send("boom")
            return await outcome
        }

        #expect(thrown is Boom, "expected Boom, got \(String(describing: thrown))")
        #expect(values.elements == ["a-x"])
        // Both the failed inner's source and the upstream are released.
        try await withThrowingTimeout(.seconds(5)) {
            try await innerSource.waitForSubscribers(atMost: 0)
            try await upstream.waitForSubscribers(atMost: 0)
        }
    }

    @Test("nothing is emitted after an inner failure, even when the upstream emits again")
    func innerFailureEmitsNothingAfterError() async throws {
        let upstream = MutableStateFlow("a")
        let transformed = Recorder<String>()
        let flow = upstream.asFlow()
            .mapThrowing { $0 }
            .flatMapLatest { value -> ThrowingFlow<String> in
                transformed.record(value)
                return ThrowingFlow<String> { collector in
                    try await collector.emit("result-\(value)")
                    throw Boom()
                }
            }
        let events = Recorder<Event>()

        try await withThrowingTimeout(.seconds(5)) {
            do {
                try await flow.collect { events.record(.value($0)) }
                events.record(.completed)
            } catch let error as Boom {
                events.record(.failure(error))
            } catch {
                events.record(.otherFailure(String(describing: error)))
            }
        }

        // The upstream is released, then emits again. The new value must not
        // start an inner or reach the collector.
        try await withThrowingTimeout(.seconds(5)) {
            try await upstream.waitForSubscribers(atMost: 0)
        }
        upstream.send("b")

        #expect(events.elements == [.value("result-a"), .failure(Boom())])
        #expect(transformed.elements == ["a"])
    }

    @Test("an upstream failure cancels an inner parked on a never-completing source")
    func upstreamFailureCancelsParkedInner() async throws {
        let innerSource = MutableStateFlow("x")
        let failUpstream = Signal()
        let upstream = ThrowingFlow<Int> { collector in
            try await collector.emit(1)
            await failUpstream.wait()
            throw Boom()
        }
        let flow = upstream.flatMapLatest { _ -> ThrowingFlow<String> in
            innerSource.asFlow().mapThrowing { $0 }
        }

        let thrown = try await withThrowingTimeout(.seconds(5)) { () async throws -> (any Error)? in
            async let outcome = failure(of: flow, recording: Recorder<String>())
            // The inner is attached to its source and will never complete on its own.
            try await innerSource.waitForSubscribers(1)
            failUpstream.fire()
            return await outcome
        }
        #expect(thrown is Boom, "expected Boom, got \(String(describing: thrown))")

        let released = (try? await withThrowingTimeout(.seconds(5)) {
            try await innerSource.waitForSubscribers(atMost: 0)
            return true
        }) ?? false
        #expect(released, "the upstream failure must cancel the parked inner, but it is still subscribed")
    }

    @Test("cancelling the collection after the upstream completes cancels a parked inner")
    func downstreamCancellationAfterUpstreamCompletesCancelsParkedInner() async throws {
        let innerSource = MutableStateFlow("x")
        // Emits once and completes, so the operator is in its wait for the inner.
        let upstream = ThrowingFlow<Int> { collector in
            try await collector.emit(1)
        }
        let collector = Task {
            try? await upstream.flatMapLatest { _ -> ThrowingFlow<String> in
                innerSource.asFlow().mapThrowing { $0 }
            }.collect { _ in }
        }
        try await withThrowingTimeout(.seconds(5)) {
            try await innerSource.waitForSubscribers(1)
        }

        collector.cancel()
        let released = (try? await withThrowingTimeout(.seconds(5)) {
            try await innerSource.waitForSubscribers(atMost: 0)
            return true
        }) ?? false
        #expect(released, "cancelling the collection must reach the parked inner, but it is still subscribed")
        // Awaiting the collector here would hang if the inner leaked.
        if released { await collector.value }
    }
}

private struct Boom: Error, Equatable {}

private enum Event: Equatable, Sendable {
    case value(String)
    case completed
    case failure(Boom)
    case otherFailure(String)
}

/// Collects `flow`, recording every value, and returns the error it ended
/// with, or nil if it completed normally.
private func failure(
    of flow: ThrowingFlow<String>,
    recording values: Recorder<String>
) async -> (any Error)? {
    do {
        try await flow.collect { values.record($0) }
        return nil
    } catch {
        return error
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
        try await withThrowingTimeout(.seconds(5)) { try await upstream.waitForSubscribers(1) }
        await upstream.emit(1)
        try #require(await innerStarted.fires(safetyNet: .seconds(5)), "the inner flow never started")

        collector.cancel()
        try #require(await innerCancelled.fires(safetyNet: .seconds(5)), "the inner flow was never cancelled")
        #expect(innerCancelled.hasFired, "downstream cancellation must reach the active inner flow")
        // The collection task itself must unwind instead of hanging in the
        // operator's completion wait. Guarded so a regression fails above
        // rather than hanging the suite here.
        if innerCancelled.hasFired { await collector.value }
    }

    @Test("ThrowingFlow: cancelling the downstream collection cancels the active inner flow")
    func throwingDownstreamCancellationCancelsInner() async throws {
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
        try #require(await innerStarted.fires(safetyNet: .seconds(5)), "the inner flow never started")

        collector.cancel()
        try #require(await innerCancelled.fires(safetyNet: .seconds(5)), "the inner flow was never cancelled")
        #expect(innerCancelled.hasFired, "downstream cancellation must reach the active inner flow")
        if innerCancelled.hasFired { await collector.value }
    }
}
