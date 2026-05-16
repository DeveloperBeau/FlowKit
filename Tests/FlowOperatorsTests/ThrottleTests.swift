import Testing
import FlowCore
import FlowSharedModels
import FlowHotStreams
import FlowTesting
import FlowTestClock
@testable import FlowOperators

@Suite("throttle operator")
struct ThrottleTests {
    @Test("throttle latest=true emits newest value at interval boundaries")
    func throttleLatest() async throws {
        let clock = TestClock()
        let upstream = MutableSharedFlow<Int>(replay: 0)

        try await TestScope.run(timeout: .seconds(15)) { scope in
            let tester = try await scope.test(
                upstream.asFlow().throttle(for: .seconds(1), latest: true, clock: clock)
            )

            try? await Task.sleep(for: .seconds(0.02))

            await upstream.emit(1)   // emitted immediately (first value)
            try await tester.expectValue(1)

            await upstream.emit(2)
            await upstream.emit(3)
            // Allow collect task to process buffered values before window expires
            try? await Task.sleep(for: .seconds(0.005))
            await clock.advance(by: .seconds(1))
            try await tester.expectValue(3) // latest at boundary
        }
    }

    @Test("throttle latest=false emits first value in each window")
    func throttleFirst() async throws {
        let clock = TestClock()
        let upstream = MutableSharedFlow<Int>(replay: 0)

        try await TestScope.run(timeout: .seconds(15)) { scope in
            let tester = try await scope.test(
                upstream.asFlow().throttle(for: .seconds(1), latest: false, clock: clock)
            )

            try? await Task.sleep(for: .seconds(0.02))

            await upstream.emit(1)   // first value, emitted
            try await tester.expectValue(1)

            await upstream.emit(2)   // within window, stored
            await upstream.emit(3)   // within window, replaces 2
            // Allow collect task to process buffered values before window expires
            try? await Task.sleep(for: .seconds(0.005))
            await clock.advance(by: .seconds(1))
            // With latest=false, the FIRST value after the window started (2) is emitted
            try await tester.expectValue(2)
        }
    }
}
