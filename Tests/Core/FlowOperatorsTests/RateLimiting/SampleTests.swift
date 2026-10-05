import Testing
import FlowCore
import FlowSharedModels
import FlowHotStreams
import FlowTesting
import FlowTestSupport
import FlowTestClock
@testable import FlowOperators

@Suite("sample operator")
struct SampleTests {
    @Test("sample emits most recent value at fixed intervals")
    func emitsAtIntervals() async throws {
        let clock = TestClock()
        let upstream = MutableSharedFlow<Int>(replay: 0)
        let probe = FlowProbe<Int>()

        try await ProbeScope.run { scope in
            let tester = scope.probe(
                upstream.asFlow().tap(after: probe).sample(every: .seconds(1), clock: clock)
            )

            try await upstream.waitForSubscribers(1)

            await upstream.emit(1)
            await upstream.emit(2)
            await upstream.emit(3)
            // Wait until sample has stored the burst before advancing.
            try await probe.waitForValue { $0 == 3 }
            try #require(await clock.registersSleepers(1), "the sleepers never registered")

            await clock.advance(by: .seconds(1))
            try await tester.expectValue(3) // most recent at sample point

            await upstream.emit(10)
            try await probe.waitForValue { $0 == 10 }
            try #require(await clock.registersSleepers(1), "the sleepers never registered")
            await clock.advance(by: .seconds(1))
            try await tester.expectValue(10)
        }
    }

    @Test("sample skips interval if no value arrived since last sample")
    func skipsEmptyIntervals() async throws {
        let clock = TestClock()
        let upstream = MutableSharedFlow<Int>(replay: 0)
        let probe = FlowProbe<Int>()

        try await ProbeScope.run { scope in
            let tester = scope.probe(
                upstream.asFlow().tap(after: probe).sample(every: .seconds(1), clock: clock)
            )

            try await upstream.waitForSubscribers(1)
            // Wait until sample has registered its interval sleep before
            // advancing, rather than racing that registration.
            try #require(await clock.registersSleepers(1), "the sleepers never registered")

            // No values emitted. Advance two intervals.
            await clock.advance(by: .seconds(2))
            // The empty intervals produce nothing: the next read below is the
            // value emitted after them, so anything earlier would fail it.

            // Now emit and advance
            await upstream.emit(42)
            try await probe.waitForValue { $0 == 42 }
            try #require(await clock.registersSleepers(1), "the sleepers never registered")
            await clock.advance(by: .seconds(1))
            try await tester.expectValue(42)
        }
    }
}
