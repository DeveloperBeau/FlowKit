import Testing
import Foundation
import FlowCore
import FlowSharedModels
import FlowTestClock
@testable import FlowHotStreams

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

        await coordinator.activate()
        try? await Task.sleep(for: .seconds(0.02))
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
        try? await Task.sleep(for: .seconds(0.02))
        #expect(!upstreamStarted.withLock { $0 })

        await coordinator.subscriberDidAppear()
        try? await Task.sleep(for: .seconds(0.02))
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

        try? await Task.sleep(for: .seconds(0.02))
        #expect(!upstreamStopped.withLock { $0 })

        await clock.advance(by: .seconds(5))
        try? await Task.sleep(for: .seconds(0.02))
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

        await clock.advance(by: .seconds(4))
        await coordinator.subscriberDidAppear()

        await clock.advance(by: .seconds(10))
        try? await Task.sleep(for: .seconds(0.02))

        #expect(!upstreamStopped.withLock { $0 })
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
        await clock.advance(by: .seconds(2))

        await coordinator.subscriberDidAppear()
        await coordinator.subscriberDidDisappear()

        await clock.advance(by: .seconds(4))
        try? await Task.sleep(for: .seconds(0.02))
        #expect(!upstreamStopped.withLock { $0 })

        await clock.advance(by: .seconds(2))
        try? await Task.sleep(for: .seconds(0.02))
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
        try? await Task.sleep(for: .seconds(0.02))
        #expect(upstreamStarted.withLock { $0 })

        await coordinator.deactivate()
        try? await Task.sleep(for: .seconds(0.02))
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
        await coordinator.subscriberDidDisappear()

        try? await Task.sleep(for: .seconds(0.01))
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
        await coordinator.subscriberDidDisappear()  // still one left

        await clock.advance(by: .seconds(10))
        try? await Task.sleep(for: .seconds(0.01))
        #expect(!upstreamStopped.withLock { $0 })
        await coordinator.deactivate()
    }
}
