import Testing
import FlowCore
import FlowSharedModels
import FlowHotStreams
import FlowTesting
import FlowTestClock
@testable import FlowOperators

@Suite("debounce operator")
struct DebounceTests {
    @Test("debounce suppresses rapid emissions and emits after silence")
    func suppressesRapidEmissions() async throws {
        let clock = TestClock()
        let upstream = MutableSharedFlow<String>(replay: 0)

        try await TestScope.run(timeout: .seconds(5)) { scope in
            let tester = try await scope.test(
                upstream.asFlow().debounce(for: .milliseconds(300), clock: clock)
            )

            try? await Task.sleep(nanoseconds: 20_000_000)

            await upstream.emit("h")
            await clock.advance(by: .milliseconds(100))
            await upstream.emit("he")
            await clock.advance(by: .milliseconds(100))
            await upstream.emit("hel")

            // Not enough silence yet. No value emitted.
            await tester.expectNoValue(within: .milliseconds(50))

            // Advance past the debounce window
            await clock.advance(by: .milliseconds(300))
            try await tester.expectValue("hel")
        }
    }

    @Test("debounce emits immediately after sufficient silence")
    func emitsAfterSilence() async throws {
        let clock = TestClock()
        let upstream = MutableSharedFlow<Int>(replay: 0)

        try await TestScope.run(timeout: .seconds(5)) { scope in
            let tester = try await scope.test(
                upstream.asFlow().debounce(for: .seconds(1), clock: clock)
            )

            try? await Task.sleep(nanoseconds: 20_000_000)

            await upstream.emit(42)
            // Allow collect task to process the value and register the clock sleep
            // before we advance the clock. MutableSharedFlow.emit returns as soon
            // as the value is buffered, not after consumers process it.
            try? await Task.sleep(nanoseconds: 5_000_000)
            await clock.advance(by: .seconds(1))
            try await tester.expectValue(42)
        }
    }

    @Test("debounce on empty flow produces empty flow")
    func emptyUpstream() async throws {
        let clock = TestClock()
        let flow = Flow<Int>.empty
        try await flow.debounce(for: .seconds(1), clock: clock).test { tester in
            try await tester.expectCompletion()
        }
    }
}
