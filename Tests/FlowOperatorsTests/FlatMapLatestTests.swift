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
            try await tester.expectValue("from-1")
            try await tester.expectValue("from-2")
            try await tester.expectValue("from-3")
            try await tester.expectCompletion()
        }
    }

    @Test("flatMapLatest cancels long-running inner when new value arrives")
    func cancelsLongRunning() async throws {
        let cancelled = Mutex<[Int]>([])

        let upstream = MutableSharedFlow<Int>(replay: 0)

        try await TestScope.run(timeout: .seconds(5)) { scope in
            let resultFlow = upstream.asFlow().flatMapLatest { value -> Flow<String> in
                Flow<String> { collector in
                    await withTaskCancellationHandler {
                        // Simulate long work
                        while !Task.isCancelled {
                            await Task.yield()
                        }
                    } onCancel: {
                        cancelled.withLock { $0.append(value) }
                    }
                }
            }

            _ = try await scope.test(resultFlow)

            // Give tester time to subscribe
            try? await Task.sleep(nanoseconds: 50_000_000)

            // Emit 1. Starts inner flow for 1.
            await upstream.emit(1)
            try? await Task.sleep(nanoseconds: 50_000_000)

            // Emit 2. Should cancel inner flow for 1, start inner flow for 2.
            await upstream.emit(2)
            try? await Task.sleep(nanoseconds: 50_000_000)

            // Emit 3. Should cancel inner flow for 2, start inner flow for 3.
            await upstream.emit(3)
            try? await Task.sleep(nanoseconds: 50_000_000)

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
