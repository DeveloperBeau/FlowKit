import Testing
import FlowCore
import FlowSharedModels
import FlowTesting
@testable import FlowHotStreams

/// A cold source that stays alive until cancelled, counting how many times it
/// starts and how many times it is torn down. Used to prove that sharing
/// actually cancels the upstream when it should.
private func countingSource(started: Mutex<Int>, cancelled: Mutex<Int>) -> Flow<Int> {
    Flow<Int> { collector in
        started.withLock { $0 += 1 }
        await withTaskCancellationHandler {
            await collector.emit(1)
            while !Task.isCancelled { await Task.yield() }
        } onCancel: {
            cancelled.withLock { $0 += 1 }
        }
    }
}

@Suite("Sharing teardown")
struct SharingTeardownTests {
    @Test("whileSubscribed cancels the upstream once the last subscriber leaves")
    func stopCancelsUpstream() async {
        let started = Mutex(0)
        let cancelled = Mutex(0)
        // Zero timeout: the stop fires as soon as the last subscriber leaves,
        // so no clock advancing is needed and the test stays deterministic.
        let shared = countingSource(started: started, cancelled: cancelled)
            .asSharedFlow(replay: 1, strategy: .whileSubscribed(stopTimeout: .zero))

        let received = Mutex(false)
        let subscriber = Task { await shared.asFlow().collect { _ in received.withLock { $0 = true } } }
        while !received.withLock({ $0 }) { await Task.yield() }
        #expect(started.withLock { $0 } == 1)
        #expect(cancelled.withLock { $0 } == 0, "the upstream must still be running while a subscriber is attached")

        subscriber.cancel()
        await subscriber.value

        // Convergent: the last subscriber leaving must cancel the upstream.
        while cancelled.withLock({ $0 }) == 0 { await Task.yield() }
        #expect(cancelled.withLock { $0 } == 1, "the upstream must be cancelled once no subscribers remain")
    }

    @Test("whileSubscribed restarts the upstream when a subscriber returns after a stop")
    func upstreamRestartsAfterStop() async {
        let started = Mutex(0)
        let cancelled = Mutex(0)
        let shared = countingSource(started: started, cancelled: cancelled)
            .asSharedFlow(replay: 1, strategy: .whileSubscribed(stopTimeout: .zero))

        let firstReceived = Mutex(false)
        let first = Task { await shared.asFlow().collect { _ in firstReceived.withLock { $0 = true } } }
        while !firstReceived.withLock({ $0 }) { await Task.yield() }
        first.cancel()
        await first.value
        while cancelled.withLock({ $0 }) == 0 { await Task.yield() }

        // A new subscriber must restart the cold source, not read a dead one.
        // Wait on the restart directly (`started == 2`); waiting on a received
        // value would race, since replay hands the new subscriber the old
        // value before the restarted upstream runs.
        let second = Task { await shared.asFlow().collect { _ in } }
        while started.withLock({ $0 }) < 2 { await Task.yield() }
        #expect(started.withLock { $0 } == 2, "a returning subscriber must restart the upstream")

        second.cancel()
        await second.value
    }
}
