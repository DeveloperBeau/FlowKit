import Testing
import FlowTestSupport
import FlowCore
import FlowSharedModels
import FlowTestClock
import FlowTestingCore
@testable import FlowHotStreams

/// A cold source that flags when its collection starts and when it is torn
/// down. It idles on a real-clock sleep that only ever ends by cancellation,
/// so the stop flag setting proves the coordinator cancelled the upstream.
private struct ObservableUpstream: Sendable {
    let started = Signal()
    let stopped = Signal()

    func flow() -> Flow<Int> {
        Flow<Int> { [started, stopped] collector in
            await collector.emit(1)
            started.fire()
            // Idles until the sharing coordinator cancels the upstream task.
            await parkUntilCancelled()
            stopped.fire()
        }
    }
}

@Suite("whileSubscribed default stop timeout")
struct WhileSubscribedDefaultTests {
    @Test("asSharedFlow default strategy stops upstream immediately when last subscriber leaves")
    func sharedFlowDefaultStopsImmediately() async {
        let clock = TestClock()
        let upstream = ObservableUpstream()
        let shared = upstream.flow().asSharedFlow(clock: clock)

        let subscriber = Task {
            await shared.asFlow().collect { _ in }
        }
        await upstream.started.wait()
        #expect(upstream.started.hasFired)

        subscriber.cancel()
        // With a zero default stop timeout the upstream must be cancelled
        // without any clock advancement.
        await upstream.stopped.wait()
        #expect(upstream.stopped.hasFired)
        #expect(clock.sleeperCount == 0, "a zero stop timeout must never register a sleeper")
    }

    @Test("asStateFlow default strategy stops upstream immediately when last subscriber leaves")
    func stateFlowDefaultStopsImmediately() async {
        let clock = TestClock()
        let upstream = ObservableUpstream()
        let state = upstream.flow().asStateFlow(initialValue: 0, clock: clock)

        let subscriber = Task {
            await state.asFlow().collect { _ in }
        }
        await upstream.started.wait()
        #expect(upstream.started.hasFired)

        subscriber.cancel()
        await upstream.stopped.wait()
        #expect(upstream.stopped.hasFired)
        #expect(clock.sleeperCount == 0, "a zero stop timeout must never register a sleeper")
    }

    @Test("explicit stop timeout is still honored with the strategy clock")
    func explicitStopTimeoutStillHonored() async throws {
        let clock = TestClock()
        let upstream = ObservableUpstream()
        let shared = upstream.flow().asSharedFlow(
            strategy: .whileSubscribed(stopTimeout: .seconds(5)),
            clock: clock
        )

        let subscriber = Task {
            await shared.asFlow().collect { _ in }
        }
        await upstream.started.wait()

        subscriber.cancel()
        // The delayed stop registers its sleep on the strategy clock instead
        // of stopping synchronously.
        try await clock.waitForSleepers(1)
        #expect(!upstream.stopped.hasFired, "the stop must wait for the timeout")

        await clock.advance(by: .seconds(5))
        await upstream.stopped.wait()
        #expect(upstream.stopped.hasFired)
    }
}
