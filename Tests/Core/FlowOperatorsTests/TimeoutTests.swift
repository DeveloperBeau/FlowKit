import Testing
import FlowCore
import FlowSharedModels
import FlowHotStreams
import FlowTesting
import FlowTestClock
import FlowOperators

@Suite("timeout operator")
struct TimeoutTests {
    @Test("values inside the window pass; a gap beyond it fails with FlowTimeoutError")
    func gapTriggersTimeout() async throws {
        let clock = TestClock()
        let upstream = MutableSharedFlow<Int>(replay: 0)
        let probe = FlowProbe<Int>()

        let flow = upstream.asFlow()
            .tap(after: probe)
            .timeout(for: .seconds(10), clock: clock)

        try await TestScope.run(timeout: .seconds(15)) { scope in
            let tester = try await scope.test(flow)
            await waitUntil { await upstream.subscriptionCount >= 1 }
            await waitUntil { clock.sleeperCount >= 1 }

            await upstream.emit(1)
            try await tester.expectValue(1)

            // Halfway through the window a new value resets the deadline.
            await waitUntil { clock.sleeperCount >= 1 }
            await clock.advance(by: .seconds(5))
            await upstream.emit(2)
            await waitUntil { await probe.last == 2 }
            try await tester.expectValue(2)

            // Silence for a full window from the last value.
            await waitUntil { clock.sleeperCount >= 1 }
            await clock.advance(by: .seconds(10))
            try await tester.expectError(FlowTimeoutError())
        }
    }

    @Test("timeout fires before the first value if the source stays silent")
    func silentSourceTimesOut() async throws {
        let clock = TestClock()
        let upstream = MutableSharedFlow<Int>(replay: 0)
        let flow = upstream.asFlow().timeout(for: .seconds(3), clock: clock)

        try await TestScope.run(timeout: .seconds(15)) { scope in
            let tester = try await scope.test(flow)
            await waitUntil { await upstream.subscriptionCount >= 1 }
            await waitUntil { clock.sleeperCount >= 1 }
            await clock.advance(by: .seconds(3))
            try await tester.expectError(FlowTimeoutError())
        }
    }

    @Test("a flow that completes in time never times out")
    func completionBeatsTimeout() async throws {
        let clock = TestClock()
        let flow = Flow(of: 1, 2).timeout(for: .seconds(5), clock: clock)

        try await TestScope.run { scope in
            let tester = try await scope.test(flow)
            try await tester.expectValue(1)
            try await tester.expectValue(2)
            try await tester.expectCompletion()
        }
    }

    @Test("an upstream error propagates unchanged, not as FlowTimeoutError")
    func upstreamErrorWins() async throws {
        struct Bad: Error, Equatable {}
        let clock = TestClock()
        let flow = ThrowingFlow<Int> { collector in
            try await collector.emit(1)
            throw Bad()
        }.timeout(for: .seconds(5), clock: clock)

        try await TestScope.run { scope in
            let tester = try await scope.test(flow)
            try await tester.expectValue(1)
            try await tester.expectError(Bad())
        }
    }
}
