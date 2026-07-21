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

        try await TestScope.run(timeout: .seconds(15)) { scope in
            let tester = try await scope.test(
                upstream.asFlow().debounce(for: .milliseconds(300), clock: clock)
            )

            // Wait for the debounce to subscribe before emitting; replay:0
            // drops anything sent before the subscription is live.
            await waitUntil { await upstream.subscriptionCount >= 1 }

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

        try await TestScope.run(timeout: .seconds(15)) { scope in
            let tester = try await scope.test(
                upstream.asFlow().debounce(for: .seconds(1), clock: clock)
            )

            await waitUntil { await upstream.subscriptionCount >= 1 }

            await upstream.emit(42)
            // Wait until the debounce has registered its clock sleep before
            // advancing, instead of racing that registration with a real sleep.
            await waitUntil { clock.sleeperCount >= 1 }
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
