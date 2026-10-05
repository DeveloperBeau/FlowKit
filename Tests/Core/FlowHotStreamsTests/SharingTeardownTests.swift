import Testing
import FlowCore
import FlowSharedModels
import FlowTesting
import FlowTestSupport
@testable import FlowHotStreams

/// A cold source that stays alive until cancelled, counting how many times it
/// starts and how many times it is torn down. Used to prove that sharing
/// actually cancels the upstream when it should.
private func countingSource(started: Recorder<Void>, cancelled: Recorder<Void>) -> Flow<Int> {
    Flow<Int> { collector in
        started.record(())
        await withTaskCancellationHandler {
            await collector.emit(1)
            await parkUntilCancelled()
        } onCancel: {
            cancelled.record(())
        }
    }
}

@Suite("Sharing teardown")
struct SharingTeardownTests {
    @Test("whileSubscribed cancels the upstream once the last subscriber leaves")
    func stopCancelsUpstream() async {
        let started = Recorder<Void>()
        let cancelled = Recorder<Void>()
        // Zero timeout: the stop fires as soon as the last subscriber leaves,
        // so no clock advancing is needed and the test stays deterministic.
        let shared = countingSource(started: started, cancelled: cancelled)
            .asSharedFlow(replay: 1, strategy: .whileSubscribed(stopTimeout: .zero))

        let received = Signal()
        let subscriber = Task { await shared.asFlow().collect { _ in received.fire() } }
        await received.wait()
        #expect(started.count == 1)
        #expect(cancelled.count == 0, "the upstream must still be running while a subscriber is attached")

        subscriber.cancel()
        await subscriber.value

        // The last subscriber leaving must cancel the upstream.
        await cancelled.wait(atLeast: 1)
        #expect(cancelled.count == 1, "the upstream must be cancelled once no subscribers remain")
    }

    @Test("whileSubscribed restarts the upstream when a subscriber returns after a stop")
    func upstreamRestartsAfterStop() async {
        let started = Recorder<Void>()
        let cancelled = Recorder<Void>()
        let shared = countingSource(started: started, cancelled: cancelled)
            .asSharedFlow(replay: 1, strategy: .whileSubscribed(stopTimeout: .zero))

        let firstReceived = Signal()
        let first = Task { await shared.asFlow().collect { _ in firstReceived.fire() } }
        await firstReceived.wait()
        first.cancel()
        await first.value
        await cancelled.wait(atLeast: 1)

        // A new subscriber must restart the cold source, not read a dead one.
        // Wait on the restart directly (`started == 2`); waiting on a received
        // value would race, since replay hands the new subscriber the old
        // value before the restarted upstream runs.
        let second = Task { await shared.asFlow().collect { _ in } }
        await started.wait(atLeast: 2)
        #expect(started.count == 2, "a returning subscriber must restart the upstream")

        second.cancel()
        await second.value
    }
}
