import Testing
import FlowTestSupport
import Foundation
import FlowCore
import FlowSharedModels
import FlowTestClock
import FlowTestingCore
@testable import FlowHotStreams

/// Yields a bounded number of times so a "did not happen" assertion gives the
/// wrong behaviour every scheduling chance to occur before it is checked.
private func settle() async {
    for _ in 0..<100 { await Task.yield() }
}

/// Builds a coordinator whose start, stop and replay reset fire signals, so a
/// test can assert on each independently.
private func makeCoordinator(
    stopTimeout: Duration,
    replayExpiration: Duration,
    clock: TestClock,
    stopped: Signal,
    resets: Recorder<Void>
) -> SharingCoordinator {
    SharingCoordinator(
        strategy: .whileSubscribed(stopTimeout: stopTimeout, replayExpiration: replayExpiration),
        clock: clock,
        start: {},
        stop: { stopped.fire() },
        resetReplay: { resets.record(()) }
    )
}

@Suite("SharingCoordinator replay expiration")
struct ReplayExpirationCoordinatorTests {
    @Test("replay is reset once replayExpiration elapses after the last subscriber leaves")
    func resetsAfterExpiration() async throws {
        let clock = TestClock()
        let stopped = Signal()
        let resets = Recorder<Void>()
        let coordinator = makeCoordinator(
            stopTimeout: .zero, replayExpiration: .seconds(3),
            clock: clock, stopped: stopped, resets: resets
        )
        await coordinator.activate()
        await coordinator.subscriberDidAppear()
        await coordinator.subscriberDidDisappear()
        try #require(await clock.registersSleepers(1), "the expiration sleep never registered")

        await clock.advance(by: .seconds(2))
        await settle()
        #expect(resets.count == 0, "the replay must survive until replayExpiration elapses")

        await clock.advance(by: .seconds(1))
        await resets.wait(atLeast: 1)
        #expect(resets.count == 1)
        await coordinator.deactivate()
    }

    @Test("a subscriber returning before replayExpiration keeps the replay")
    func returningSubscriberKeepsReplay() async throws {
        let clock = TestClock()
        let stopped = Signal()
        let resets = Recorder<Void>()
        let coordinator = makeCoordinator(
            stopTimeout: .zero, replayExpiration: .seconds(3),
            clock: clock, stopped: stopped, resets: resets
        )
        await coordinator.activate()
        await coordinator.subscriberDidAppear()
        await coordinator.subscriberDidDisappear()
        try #require(await clock.registersSleepers(1), "the expiration sleep never registered")

        await clock.advance(by: .seconds(2))
        await coordinator.subscriberDidAppear() // cancels the pending reset
        try await clock.waitForNoSleepers()
        await clock.advance(by: .seconds(10))
        await settle()
        #expect(resets.count == 0, "a returning subscriber must cancel the reset")
        await coordinator.deactivate()
    }

    @Test("zero replayExpiration resets the replay before subscriberDidDisappear returns")
    func zeroExpirationResetsAtOnce() async {
        let clock = TestClock()
        let stopped = Signal()
        let resets = Recorder<Void>()
        let coordinator = makeCoordinator(
            stopTimeout: .zero, replayExpiration: .zero,
            clock: clock, stopped: stopped, resets: resets
        )
        await coordinator.activate()
        await coordinator.subscriberDidAppear()
        #expect(resets.count == 0, "nothing resets while a subscriber is attached")
        await coordinator.subscriberDidDisappear()
        #expect(resets.count == 1)
        #expect(clock.sleeperCount == 0, "a zero expiration must never register a sleeper")
        await coordinator.deactivate()
    }

    @Test("a remaining subscriber prevents the replay reset")
    func remainingSubscriberPreventsReset() async {
        let clock = TestClock()
        let stopped = Signal()
        let resets = Recorder<Void>()
        let coordinator = makeCoordinator(
            stopTimeout: .zero, replayExpiration: .zero,
            clock: clock, stopped: stopped, resets: resets
        )
        await coordinator.activate()
        await coordinator.subscriberDidAppear()
        await coordinator.subscriberDidAppear()
        await coordinator.subscriberDidDisappear()
        #expect(resets.count == 0, "the replay must survive while a subscriber is attached")
        await coordinator.deactivate()
    }

    @Test("replayExpiration shorter than stopTimeout resets the replay before the upstream stops")
    func expirationShorterThanStopTimeout() async throws {
        let clock = TestClock()
        let stopped = Signal()
        let resets = Recorder<Void>()
        let coordinator = makeCoordinator(
            stopTimeout: .seconds(5), replayExpiration: .seconds(2),
            clock: clock, stopped: stopped, resets: resets
        )
        await coordinator.activate()
        await coordinator.subscriberDidAppear()
        await coordinator.subscriberDidDisappear()
        try await clock.waitForSleepers(2)

        await clock.advance(by: .seconds(2))
        await resets.wait(atLeast: 1)
        await settle()
        #expect(resets.count == 1, "the replay expires 2 s after the last subscriber left")
        #expect(!stopped.hasFired, "the upstream keeps running until stopTimeout")

        await clock.advance(by: .seconds(3))
        await stopped.wait()
        #expect(resets.count == 1, "the stop must not reset the replay a second time")
        await coordinator.deactivate()
    }

    @Test("replayExpiration longer than stopTimeout resets the replay after the upstream stops")
    func expirationLongerThanStopTimeout() async throws {
        let clock = TestClock()
        let stopped = Signal()
        let resets = Recorder<Void>()
        let coordinator = makeCoordinator(
            stopTimeout: .seconds(2), replayExpiration: .seconds(5),
            clock: clock, stopped: stopped, resets: resets
        )
        await coordinator.activate()
        await coordinator.subscriberDidAppear()
        await coordinator.subscriberDidDisappear()
        try await clock.waitForSleepers(2)

        await clock.advance(by: .seconds(2))
        await stopped.wait()
        await settle()
        #expect(resets.count == 0, "the replay outlives the upstream until replayExpiration")

        // Counted from the last unsubscribe, not from the stop: 3 s more, not 5.
        await clock.advance(by: .seconds(3))
        await resets.wait(atLeast: 1)
        #expect(resets.count == 1)
        await coordinator.deactivate()
    }

    @Test("each resubscribe cycle restarts the expiration and resets once per expiry")
    func multipleCycles() async throws {
        let clock = TestClock()
        let stopped = Signal()
        let resets = Recorder<Void>()
        let coordinator = makeCoordinator(
            stopTimeout: .zero, replayExpiration: .seconds(3),
            clock: clock, stopped: stopped, resets: resets
        )
        await coordinator.activate()

        for cycle in 1...3 {
            await coordinator.subscriberDidAppear()
            await coordinator.subscriberDidDisappear()
            try await clock.waitForSleepers(1)
            await clock.advance(by: .seconds(2))
            await coordinator.subscriberDidAppear() // a quick return keeps the replay
            try await clock.waitForNoSleepers()
            await coordinator.subscriberDidDisappear()
            try await clock.waitForSleepers(1)
            // The fresh expiration counts from this leave, so 2 s is not enough.
            await clock.advance(by: .seconds(2))
            await settle()
            #expect(resets.count == cycle - 1, "cycle \(cycle) reset before its fresh expiration")
            await clock.advance(by: .seconds(1))
            await resets.wait(atLeast: cycle)
            #expect(resets.count == cycle, "cycle \(cycle) did not reset after its expiration")
        }
        await coordinator.deactivate()
    }

    @Test("deactivate while the expiration is pending cancels the reset")
    func deactivateCancelsPendingReset() async throws {
        let clock = TestClock()
        let stopped = Signal()
        let resets = Recorder<Void>()
        let coordinator = makeCoordinator(
            stopTimeout: .zero, replayExpiration: .seconds(3),
            clock: clock, stopped: stopped, resets: resets
        )
        await coordinator.activate()
        await coordinator.subscriberDidAppear()
        await coordinator.subscriberDidDisappear()
        try await clock.waitForSleepers(1)

        await coordinator.deactivate()
        try await clock.waitForNoSleepers()
        await clock.advance(by: .seconds(10))
        await settle()
        #expect(resets.count == 0, "a deactivated coordinator must not reset the replay")
    }

    @Test("eager and lazy strategies never reset the replay")
    func eagerAndLazyNeverReset() async {
        for strategy in [SharingStrategy.eager, .lazy] {
            let resets = Recorder<Void>()
            let coordinator = SharingCoordinator(
                strategy: strategy, clock: TestClock(),
                start: {}, stop: {}, resetReplay: { resets.record(()) }
            )
            await coordinator.activate()
            await coordinator.subscriberDidAppear()
            await coordinator.subscriberDidDisappear()
            await settle()
            #expect(resets.count == 0, "\(strategy) must keep the replay")
            await coordinator.deactivate()
        }
    }
}

/// A cold source that emits its start number (1 on the first start, 2 on the
/// second, ...) and then idles until cancelled. A subscriber whose first value
/// is a lower number than the current start received a stale replay.
private final class NumberedUpstream: Sendable {
    private let starts = Mutex(0)
    let emitted = Recorder<Int>()

    func flow() -> Flow<Int> {
        Flow<Int> { [starts, emitted] collector in
            let number = starts.withLock { count -> Int in
                count += 1
                return count
            }
            await collector.emit(number)
            emitted.record(number)
            await parkUntilCancelled()
        }
    }
}

/// Collects the first value of `flow` and returns it.
private func firstValue(of flow: Flow<Int>) async -> Int? {
    let first = Mutex<Int?>(nil)
    let received = Signal()
    let task = Task {
        await flow.collect { value in
            first.withLock { if $0 == nil { $0 = value } }
            received.fire()
        }
    }
    await received.wait()
    task.cancel()
    await task.value
    return first.withLock { $0 }
}

@Suite("asSharedFlow replay expiration")
struct ReplayExpirationSharedFlowTests {
    @Test("zero replayExpiration: a subscriber arriving right after the last one left sees no stale value")
    func zeroExpirationNoStaleValue() async {
        let upstream = NumberedUpstream()
        let shared = upstream.flow().asSharedFlow(
            replay: 1, strategy: .whileSubscribed(stopTimeout: .zero, replayExpiration: .zero),
            clock: TestClock()
        )
        #expect(await firstValue(of: shared.asFlow()) == 1)
        // Back to back with the first subscriber's exit.
        #expect(await firstValue(of: shared.asFlow()) == 2, "the second subscriber received the stale replay")
        #expect(await firstValue(of: shared.asFlow()) == 3, "the third subscriber received the stale replay")
    }

    @Test("zero replayExpiration with a running upstream: a returning subscriber sees no stale value")
    func zeroExpirationWithStopTimeoutNoStaleValue() async throws {
        let clock = TestClock()
        let upstream = NumberedUpstream()
        let shared = upstream.flow().asSharedFlow(
            replay: 1, strategy: .whileSubscribed(stopTimeout: .seconds(5), replayExpiration: .zero),
            clock: clock
        )
        let first = Task { await shared.asFlow().collect { _ in } }
        await upstream.emitted.wait(atLeast: 1)
        first.cancel()
        await first.value
        try await clock.waitForSleepers(1)

        // The upstream is still running, so nothing re-emits: the replay must be empty.
        let leftover = Recorder<Int>()
        let second = Task { await shared.asFlow().collect { leftover.record($0) } }
        try await (shared as? any SubscriberCountWaiting)?.waitForSubscribers(1)
        await settle()
        #expect(leftover.elements.isEmpty, "the returning subscriber received the stale replay")
        second.cancel()
        await second.value
    }

    @Test("non-zero replayExpiration keeps the replay for a subscriber returning in time")
    func replayKeptWithinExpiration() async throws {
        let clock = TestClock()
        let upstream = NumberedUpstream()
        let shared = upstream.flow().asSharedFlow(
            replay: 1, strategy: .whileSubscribed(stopTimeout: .zero, replayExpiration: .seconds(5)),
            clock: clock
        )
        #expect(await firstValue(of: shared.asFlow()) == 1)
        try await clock.waitForSleepers(1)
        await clock.advance(by: .seconds(4))
        #expect(await firstValue(of: shared.asFlow()) == 1, "the replay must survive inside the expiration")
    }

    @Test("non-zero replayExpiration clears the replay once it elapses")
    func replayClearedAfterExpiration() async throws {
        let clock = TestClock()
        let upstream = NumberedUpstream()
        let shared = upstream.flow().asSharedFlow(
            replay: 1, strategy: .whileSubscribed(stopTimeout: .zero, replayExpiration: .seconds(5)),
            clock: clock
        )
        #expect(await firstValue(of: shared.asFlow()) == 1)
        try await clock.waitForSleepers(1)
        await clock.advance(by: .seconds(5))
        try await clock.waitForNoSleepers()
        await settle()
        #expect(await firstValue(of: shared.asFlow()) == 2, "the expired replay was delivered")
    }

    @Test("asStateFlow keeps its value after replayExpiration: a state flow always has a value")
    func stateFlowKeepsValue() async throws {
        let clock = TestClock()
        let upstream = NumberedUpstream()
        let state = upstream.flow().asStateFlow(
            initialValue: 0,
            strategy: .whileSubscribed(stopTimeout: .zero, replayExpiration: .zero),
            clock: clock
        )
        let subscriber = Task { await state.asFlow().collect { _ in } }
        await upstream.emitted.wait(atLeast: 1)
        subscriber.cancel()
        await subscriber.value
        await settle()
        #expect(state.value == 1, "replayExpiration must not reset a StateFlow's value")
    }
}
