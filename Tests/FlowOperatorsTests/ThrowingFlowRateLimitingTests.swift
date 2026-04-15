import Testing
import FlowCore
import FlowHotStreams
import FlowTesting
import FlowTestClock
@testable import FlowOperators

@Suite("ThrowingFlow rate-limiting operators")
struct ThrowingFlowRateLimitingTests {
    // MARK: - debounce

    @Test("ThrowingFlow.debounce emits after silence")
    func debounceEmitsAfterSilence() async throws {
        let clock = TestClock()
        let upstream = MutableSharedFlow<Int>(replay: 0)

        try await TestScope.run(timeout: .seconds(5)) { scope in
            let tester = try await scope.test(
                ThrowingFlow<Int> { collector in
                    for await value in upstream.asFlow().asAsyncStream() {
                        try await collector.emit(value)
                    }
                }.debounce(for: .seconds(1), clock: clock)
            )

            try? await Task.sleep(for: .seconds(0.02))
            await upstream.emit(42)
            try? await Task.sleep(for: .seconds(0.005))
            await clock.advance(by: .seconds(1))
            try await tester.expectValue(42)
        }
    }

    @Test("ThrowingFlow.debounce propagates errors")
    func debouncePropagatesError() async throws {
        struct DebounceError: Error, Equatable {}
        let flow = ThrowingFlow<Int> { _ in throw DebounceError() }
        let clock = TestClock()
        try await flow.debounce(for: .seconds(1), clock: clock).test { tester in
            try await tester.expectError(DebounceError())
        }
    }

    // MARK: - throttle

    @Test("ThrowingFlow.throttle emits first value immediately")
    func throttleFirstValue() async throws {
        let clock = TestClock()
        let upstream = MutableSharedFlow<Int>(replay: 0)

        try await TestScope.run(timeout: .seconds(5)) { scope in
            let tester = try await scope.test(
                ThrowingFlow<Int> { collector in
                    for await value in upstream.asFlow().asAsyncStream() {
                        try await collector.emit(value)
                    }
                }.throttle(for: .seconds(1), clock: clock)
            )

            try? await Task.sleep(for: .seconds(0.02))
            await upstream.emit(1)
            try await tester.expectValue(1)
        }
    }

    @Test("ThrowingFlow.throttle propagates errors")
    func throttlePropagatesError() async throws {
        struct ThrottleError: Error, Equatable {}
        let flow = ThrowingFlow<Int> { _ in throw ThrottleError() }
        let clock = TestClock()
        try await flow.throttle(for: .seconds(1), clock: clock).test { tester in
            try await tester.expectError(ThrottleError())
        }
    }

    // MARK: - removeDuplicates

    @Test("ThrowingFlow.removeDuplicates drops consecutive equals")
    func removeDuplicatesDrops() async throws {
        let flow = ThrowingFlow(of: 1, 1, 2, 2, 3)
        try await flow.removeDuplicates().test { tester in
            try await tester.expectValue(1)
            try await tester.expectValue(2)
            try await tester.expectValue(3)
            try await tester.expectCompletion()
        }
    }

    @Test("ThrowingFlow.removeDuplicates with predicate")
    func removeDuplicatesByPredicate() async throws {
        let flow = ThrowingFlow(of: "Hello", "HELLO", "World")
        try await flow.removeDuplicates(by: { $0.lowercased() == $1.lowercased() }).test { tester in
            try await tester.expectValue("Hello")
            try await tester.expectValue("World")
            try await tester.expectCompletion()
        }
    }

    @Test("ThrowingFlow.removeDuplicates propagates errors")
    func removeDuplicatesPropagatesError() async throws {
        struct DedupError: Error, Equatable {}
        let flow = ThrowingFlow<Int> { collector in
            try await collector.emit(1)
            throw DedupError()
        }
        try await flow.removeDuplicates().test { tester in
            try await tester.expectValue(1)
            try await tester.expectError(DedupError())
        }
    }

    // MARK: - sample

    @Test("ThrowingFlow.sample emits at intervals")
    func sampleEmitsAtIntervals() async throws {
        let clock = TestClock()
        let upstream = MutableSharedFlow<Int>(replay: 0)

        try await TestScope.run(timeout: .seconds(5)) { scope in
            let tester = try await scope.test(
                ThrowingFlow<Int> { collector in
                    for await value in upstream.asFlow().asAsyncStream() {
                        try await collector.emit(value)
                    }
                }.sample(every: .seconds(1), clock: clock)
            )

            try? await Task.sleep(for: .seconds(0.02))
            await upstream.emit(1)
            await upstream.emit(2)
            try? await Task.sleep(for: .seconds(0.005))
            await clock.advance(by: .seconds(1))
            try await tester.expectValue(2)
        }
    }

    @Test("ThrowingFlow.sample propagates errors")
    func samplePropagatesError() async throws {
        struct SampleError: Error, Equatable {}
        let flow = ThrowingFlow<Int> { _ in throw SampleError() }
        let clock = TestClock()
        try await flow.sample(every: .seconds(1), clock: clock).test { tester in
            try await tester.expectError(SampleError())
        }
    }
}
