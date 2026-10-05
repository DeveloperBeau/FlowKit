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

/// Yields until the delayed-stop sleep is registered on the clock, so advancing
/// the clock deterministically wakes it rather than firing before it exists.
private func waitForSleeper(_ clock: TestClock) async {
    await pollUntil { clock.sleeperCount >= 1 }
}

/// Yields until the clock has no sleepers, i.e. a cancelled stop's sleep has
/// been torn down before the next one is scheduled.
private func waitForNoSleepers(_ clock: TestClock) async {
    await pollUntil { clock.sleeperCount == 0 }
}

@Suite("SharingCoordinator")
struct SharingCoordinatorTests {
    @Test("eager starts immediately without subscribers")
    func eagerStartsImmediately() async {
        let upstreamStarted = Mutex(false)
        let coordinator = SharingCoordinator(
            strategy: .eager,
            clock: TestClock(),
            start: { upstreamStarted.withLock { $0 = true } },
            stop: {}
        )

        // activate runs the start closure synchronously for eager.
        await coordinator.activate()
        #expect(upstreamStarted.withLock { $0 })
        await coordinator.deactivate()
    }

    @Test("lazy starts on first subscriber")
    func lazyStartsOnFirstSubscriber() async {
        let upstreamStarted = Mutex(false)
        let coordinator = SharingCoordinator(
            strategy: .lazy,
            clock: TestClock(),
            start: { upstreamStarted.withLock { $0 = true } },
            stop: {}
        )

        await coordinator.activate()
        #expect(!upstreamStarted.withLock { $0 })

        // subscriberDidAppear runs the start closure synchronously.
        await coordinator.subscriberDidAppear()
        #expect(upstreamStarted.withLock { $0 })
        await coordinator.deactivate()
    }

    @Test("whileSubscribed stops after timeout when last subscriber leaves")
    func whileSubscribedBasic() async {
        let clock = TestClock()
        let upstreamStopped = Signal()

        let coordinator = SharingCoordinator(
            strategy: .whileSubscribed(stopTimeout: .seconds(5)),
            clock: clock,
            start: {},
            stop: { upstreamStopped.fire() }
        )
        await coordinator.activate()
        await coordinator.subscriberDidAppear()
        await coordinator.subscriberDidDisappear()

        await waitForSleeper(clock)
        #expect(!upstreamStopped.hasFired, "the stop must not fire before the timeout elapses")

        await clock.advance(by: .seconds(5))
        await upstreamStopped.wait()
        #expect(upstreamStopped.hasFired)
        await coordinator.deactivate()
    }

    @Test("whileSubscribed cancels stop when new subscriber arrives")
    func whileSubscribedRaceCancelsOnReappear() async {
        let clock = TestClock()
        let upstreamStopped = Signal()

        let coordinator = SharingCoordinator(
            strategy: .whileSubscribed(stopTimeout: .seconds(5)),
            clock: clock,
            start: {},
            stop: { upstreamStopped.fire() }
        )
        await coordinator.activate()
        await coordinator.subscriberDidAppear()
        await coordinator.subscriberDidDisappear()
        await waitForSleeper(clock)

        await clock.advance(by: .seconds(4))
        await coordinator.subscriberDidAppear() // cancels the pending stop

        await clock.advance(by: .seconds(10))
        await settle()
        #expect(!upstreamStopped.hasFired, "a returning subscriber must cancel the stop")
        await coordinator.deactivate()
    }

    @Test("whileSubscribed stop fires correctly after re-appear and re-leave")
    func whileSubscribedRaceFiresAfterReappearAndReleave() async {
        let clock = TestClock()
        let upstreamStopped = Signal()

        let coordinator = SharingCoordinator(
            strategy: .whileSubscribed(stopTimeout: .seconds(5)),
            clock: clock,
            start: {},
            stop: { upstreamStopped.fire() }
        )
        await coordinator.activate()

        await coordinator.subscriberDidAppear()
        await coordinator.subscriberDidDisappear()
        await waitForSleeper(clock)
        await clock.advance(by: .seconds(2))

        await coordinator.subscriberDidAppear() // cancels the pending stop
        await waitForNoSleepers(clock) // the cancelled stop's sleep is torn down
        await coordinator.subscriberDidDisappear() // schedules a fresh stop
        await waitForSleeper(clock)

        await clock.advance(by: .seconds(4))
        await settle()
        #expect(!upstreamStopped.hasFired, "the fresh timeout has not elapsed yet")

        await clock.advance(by: .seconds(2))
        await upstreamStopped.wait()
        #expect(upstreamStopped.hasFired)
        await coordinator.deactivate()
    }

    @Test("activate -> deactivate runs lifecycle correctly")
    func activateDeactivate() async {
        let upstreamStarted = Mutex(false)
        let upstreamStopped = Signal()

        let coordinator = SharingCoordinator(
            strategy: .eager,
            clock: TestClock(),
            start: { upstreamStarted.withLock { $0 = true } },
            stop: { upstreamStopped.fire() }
        )
        await coordinator.activate()
        #expect(upstreamStarted.withLock { $0 })

        // deactivate runs the stop closure synchronously.
        await coordinator.deactivate()
        #expect(upstreamStopped.hasFired)
    }

    @Test("whileSubscribed with zero timeout stops immediately")
    func whileSubscribedZeroTimeout() async {
        let upstreamStopped = Signal()
        let coordinator = SharingCoordinator(
            strategy: .whileSubscribed(stopTimeout: .zero),
            clock: TestClock(),
            start: {},
            stop: { upstreamStopped.fire() }
        )
        await coordinator.activate()
        await coordinator.subscriberDidAppear()
        // Zero timeout stops synchronously as the last subscriber leaves.
        await coordinator.subscriberDidDisappear()
        #expect(upstreamStopped.hasFired)
        await coordinator.deactivate()
    }

    @Test("multiple subscribers prevent stop even with whileSubscribed")
    func multipleSubscribersPreventsStop() async {
        let clock = TestClock()
        let upstreamStopped = Signal()

        let coordinator = SharingCoordinator(
            strategy: .whileSubscribed(stopTimeout: .seconds(1)),
            clock: clock,
            start: {},
            stop: { upstreamStopped.fire() }
        )
        await coordinator.activate()
        await coordinator.subscriberDidAppear()
        await coordinator.subscriberDidAppear()
        await coordinator.subscriberDidDisappear() // still one subscriber left

        await clock.advance(by: .seconds(10))
        await settle()
        #expect(!upstreamStopped.hasFired, "a remaining subscriber must keep the upstream alive")
        await coordinator.deactivate()
    }
}
