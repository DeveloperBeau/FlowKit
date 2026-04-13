import Testing
import FlowCore
import FlowSharedModels
import FlowHotStreams
import FlowTesting
import FlowTestClock
@testable import FlowOperators

@Suite("sample operator")
struct SampleTests {
    @Test("sample emits most recent value at fixed intervals")
    func emitsAtIntervals() async throws {
        let clock = TestClock()
        let upstream = MutableSharedFlow<Int>(replay: 0)

        try await TestScope.run(timeout: .seconds(5)) { scope in
            let tester = try await scope.test(
                upstream.asFlow().sample(every: .seconds(1), clock: clock)
            )

            try? await Task.sleep(nanoseconds: 20_000_000)

            await upstream.emit(1)
            await upstream.emit(2)
            await upstream.emit(3)
            // Allow collect task to drain all buffered values before sampling
            try? await Task.sleep(nanoseconds: 5_000_000)

            await clock.advance(by: .seconds(1))
            try await tester.expectValue(3) // most recent at sample point

            await upstream.emit(10)
            await clock.advance(by: .seconds(1))
            try await tester.expectValue(10)
        }
    }

    @Test("sample skips interval if no value arrived since last sample")
    func skipsEmptyIntervals() async throws {
        let clock = TestClock()
        let upstream = MutableSharedFlow<Int>(replay: 0)

        try await TestScope.run(timeout: .seconds(5)) { scope in
            let tester = try await scope.test(
                upstream.asFlow().sample(every: .seconds(1), clock: clock)
            )

            try? await Task.sleep(nanoseconds: 20_000_000)

            // No values emitted — advance two intervals
            await clock.advance(by: .seconds(2))
            await tester.expectNoValue(within: .milliseconds(50))

            // Now emit and advance
            await upstream.emit(42)
            await clock.advance(by: .seconds(1))
            try await tester.expectValue(42)
        }
    }
}
