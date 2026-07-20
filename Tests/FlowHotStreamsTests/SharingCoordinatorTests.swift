import Testing
import Foundation
import FlowCore
import FlowSharedModels
import FlowTestClock
@testable import FlowHotStreams

/// Yields until `flag` is set. The delayed stop fires on the coordinator actor
/// after the clock wakes its sleeper, so this converges on that instead of
/// racing it with a real sleep.
private func waitUntilTrue(_ flag: Mutex<Bool>) async {
    while !flag.withLock({ $0 }) { await Task.yield() }
}

/// Yields a bounded number of times so a "did not happen" assertion gives the
/// wrong behaviour every scheduling chance to occur before it is checked.
private func settle() async {
    for _ in 0..<100 { await Task.yield() }
}

/// Yields until the delayed-stop sleep is registered on the clock, so advancing
/// the clock deterministically wakes it rather than firing before it exists.
private func waitForSleeper(_ clock: TestClock) async {
    while await clock.sleeperCount < 1 { await Task.yield() }
}

/// Yields until the clock has no sleepers, i.e. a cancelled stop's sleep has
/// been torn down before the next one is scheduled.
private func waitForNoSleepers(_ clock: TestClock) async {
    while await clock.sleeperCount > 0 { await Task.yield() }
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
        let upstreamStopped = Mutex(false)

        let coordinator = SharingCoordinator(
            strategy: .whileSubscribed(stopTimeout: .seconds(5)),
            clock: clock,
            start: {},
            stop: { upstreamStopped.withLock { $0 = true } }
        )
        await coordinator.activate()
        await coordinator.subscriberDidAppear()
        await coordinator.subscriberDidDisappear()

        await waitForSleeper(clock)
        #expect(!upstreamStopped.withLock { $0 }, "the stop must not fire before the timeout elapses")

        await clock.advance(by: .seconds(5))
        await waitUntilTrue(upstreamStopped)
        #expect(upstreamStopped.withLock { $0 })
        await coordinator.deactivate()
    }

    @Test("whileSubscribed cancels stop when new subscriber arrives")
    func whileSubscribedRaceCancelsOnReappear() async {
        let clock = TestClock()
        let upstreamStopped = Mutex(false)

        let coordinator = SharingCoordinator(
            strategy: .whileSubscribed(stopTimeout: .seconds(5)),
            clock: clock,
            start: {},
            stop: { upstreamStopped.withLock { $0 = true } }
        )
        await coordinator.activate()
        await coordinator.subscriberDidAppear()
        await coordinator.subscriberDidDisappear()
        await waitForSleeper(clock)

        await clock.advance(by: .seconds(4))
        await coordinator.subscriberDidAppear() // cancels the pending stop

        await clock.advance(by: .seconds(10))
        await settle()
        #expect(!upstreamStopped.withLock { $0 }, "a returning subscriber must cancel the stop")
        await coordinator.deactivate()
    }

    @Test("whileSubscribed stop fires correctly after re-appear and re-leave")
    func whileSubscribedRaceFiresAfterReappearAndReleave() async {
        let clock = TestClock()
        let upstreamStopped = Mutex(false)

        let coordinator = SharingCoordinator(
            strategy: .whileSubscribed(stopTimeout: .seconds(5)),
            clock: clock,
            start: {},
            stop: { upstreamStopped.withLock { $0 = true } }
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
        #expect(!upstreamStopped.withLock { $0 }, "the fresh timeout has not elapsed yet")

        await clock.advance(by: .seconds(2))
        await waitUntilTrue(upstreamStopped)
        #expect(upstreamStopped.withLock { $0 })
        await coordinator.deactivate()
    }

    @Test("activate -> deactivate runs lifecycle correctly")
    func activateDeactivate() async {
        let upstreamStarted = Mutex(false)
        let upstreamStopped = Mutex(false)

        let coordinator = SharingCoordinator(
            strategy: .eager,
            clock: TestClock(),
            start: { upstreamStarted.withLock { $0 = true } },
            stop: { upstreamStopped.withLock { $0 = true } }
        )
        await coordinator.activate()
        #expect(upstreamStarted.withLock { $0 })

        // deactivate runs the stop closure synchronously.
        await coordinator.deactivate()
        #expect(upstreamStopped.withLock { $0 })
    }

    @Test("whileSubscribed with zero timeout stops immediately")
    func whileSubscribedZeroTimeout() async {
        let upstreamStopped = Mutex(false)
        let coordinator = SharingCoordinator(
            strategy: .whileSubscribed(stopTimeout: .zero),
            clock: TestClock(),
            start: {},
            stop: { upstreamStopped.withLock { $0 = true } }
        )
        await coordinator.activate()
        await coordinator.subscriberDidAppear()
        // Zero timeout stops synchronously as the last subscriber leaves.
        await coordinator.subscriberDidDisappear()
        #expect(upstreamStopped.withLock { $0 })
        await coordinator.deactivate()
    }

    @Test("multiple subscribers prevent stop even with whileSubscribed")
    func multipleSubscribersPreventsStop() async {
        let clock = TestClock()
        let upstreamStopped = Mutex(false)

        let coordinator = SharingCoordinator(
            strategy: .whileSubscribed(stopTimeout: .seconds(1)),
            clock: clock,
            start: {},
            stop: { upstreamStopped.withLock { $0 = true } }
        )
        await coordinator.activate()
        await coordinator.subscriberDidAppear()
        await coordinator.subscriberDidAppear()
        await coordinator.subscriberDidDisappear() // still one subscriber left

        await clock.advance(by: .seconds(10))
        await settle()
        #expect(!upstreamStopped.withLock { $0 }, "a remaining subscriber must keep the upstream alive")
        await coordinator.deactivate()
    }
}
