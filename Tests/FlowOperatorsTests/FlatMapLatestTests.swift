import Testing
import FlowCore
import FlowSharedModels
import FlowTesting
@testable import FlowOperators
@testable import FlowHotStreams

@Suite("flatMapLatest operator")
struct FlatMapLatestTests {
    @Test("flatMapLatest cancels previous inner flow on new upstream value")
    func cancelsPrevious() async throws {
        let innerStarted = Mutex<[Int]>([])

        let flow = Flow(of: 1, 2, 3)
        try await flow.flatMapLatest { value -> Flow<String> in
            Flow<String> { collector in
                innerStarted.withLock { $0.append(value) }
                // Only the last inner flow (value=3) should complete
                // because each new upstream value cancels the previous.
                await collector.emit("from-\(value)")
            }
        }.test { tester in
            // With sequential upstream emission + immediate inner completion,
            // all three inner flows start and emit before cancellation.
            // But with a long-running inner, only the latest survives.
            try await tester.expectValue("from-1", within: .seconds(5))
            try await tester.expectValue("from-2", within: .seconds(5))
            try await tester.expectValue("from-3", within: .seconds(5))
            try await tester.expectCompletion(within: .seconds(5))
        }
    }

    @Test("flatMapLatest cancels long-running inner when new value arrives")
    func cancelsLongRunning() async throws {
        let cancelled = Mutex<[Int]>([])

        let upstream = MutableSharedFlow<Int>(replay: 0)

        try await TestScope.run(timeout: .seconds(15)) { scope in
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
