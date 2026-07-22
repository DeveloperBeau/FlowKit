import Testing
import FlowCore
import FlowSharedModels
import FlowTestClock
import FlowTestingCore
@testable import FlowHotStreams

/// A cold source that flags when its collection starts and when it is torn
/// down. It idles on a real-clock sleep that only ever ends by cancellation,
/// so the stop flag setting proves the coordinator cancelled the upstream.
private struct ObservableUpstream: Sendable {
    let started = Mutex(false)
    let stopped = Mutex(false)

    func flow() -> Flow<Int> {
        Flow<Int> { [started, stopped] collector in
            await collector.emit(1)
            started.withLock { $0 = true }
            // Idles until the sharing coordinator cancels the upstream task;
            // cancellation wakes the sleep immediately.
            try? await ContinuousClock().sleep(for: .seconds(3600))
            stopped.withLock { $0 = true }
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
        await waitUntil { upstream.started.withLock { $0 } }
        #expect(upstream.started.withLock { $0 })

        subscriber.cancel()
        // With a zero default stop timeout the upstream must be cancelled
        // without any clock advancement.
        await waitUntil { upstream.stopped.withLock { $0 } }
        #expect(upstream.stopped.withLock { $0 })
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
        await waitUntil { upstream.started.withLock { $0 } }
        #expect(upstream.started.withLock { $0 })

        subscriber.cancel()
        await waitUntil { upstream.stopped.withLock { $0 } }
        #expect(upstream.stopped.withLock { $0 })
        #expect(clock.sleeperCount == 0, "a zero stop timeout must never register a sleeper")
    }

    @Test("explicit stop timeout is still honored with the strategy clock")
    func explicitStopTimeoutStillHonored() async {
        let clock = TestClock()
        let upstream = ObservableUpstream()
        let shared = upstream.flow().asSharedFlow(
            strategy: .whileSubscribed(stopTimeout: .seconds(5)),
            clock: clock
        )

        let subscriber = Task {
            await shared.asFlow().collect { _ in }
        }
        await waitUntil { upstream.started.withLock { $0 } }

        subscriber.cancel()
        // The delayed stop registers its sleep on the strategy clock instead
        // of stopping synchronously.
        await waitUntil { clock.sleeperCount >= 1 }
        #expect(!upstream.stopped.withLock { $0 }, "the stop must wait for the timeout")

        await clock.advance(by: .seconds(5))
        await waitUntil { upstream.stopped.withLock { $0 } }
        #expect(upstream.stopped.withLock { $0 })
    }
}
