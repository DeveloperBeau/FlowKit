import Testing
import FlowCore
import FlowSharedModels
import FlowTesting
@testable import FlowHotStreams

@Suite("MutableStateFlow.subscriptionCount")
struct StateFlowSubscriptionCountTests {
    @Test("count transitions 0 -> 1 -> 2 -> 1 -> 0 and gates an upstream collection")
    func countTransitionsAndGatesUpstream() async {
        let state = MutableStateFlow(0)
        #expect(await state.subscriptionCount == 0)

        // The whileSubscribed convention: the owner collects its upstream
        // use-case flow only while the UI observes the state.
        let upstreamValues = MutableSharedFlow<Int>(replay: 0)
        let upstreamActive = Mutex(false)
        var upstream: Task<Void, Never>?

        let first = Task { await state.asFlow().collect { _ in } }
        await waitUntil { await state.subscriptionCount == 1 }
        #expect(await state.subscriptionCount == 1)

        // First subscriber: start collecting the upstream into the state.
        upstream = Task {
            upstreamActive.withLock { $0 = true }
            await upstreamValues.asFlow().collect { value in state.send(value) }
        }
        await waitUntil { upstreamActive.withLock { $0 } }
        await waitUntil { await upstreamValues.subscriptionCount == 1 }
        await upstreamValues.emit(7)
        await waitUntil { state.value == 7 }
        #expect(state.value == 7, "upstream flows into the state while subscribed")

        let second = Task { await state.asFlow().collect { _ in } }
        await waitUntil { await state.subscriptionCount == 2 }
        #expect(await state.subscriptionCount == 2)

        second.cancel()
        await waitUntil { await state.subscriptionCount == 1 }
        #expect(await state.subscriptionCount == 1)

        first.cancel()
        await waitUntil { await state.subscriptionCount == 0 }
        #expect(await state.subscriptionCount == 0)

        // Zero subscribers: the gate stops the upstream collection.
        upstream?.cancel()
        await waitUntil { await upstreamValues.subscriptionCount == 0 }
        #expect(await upstreamValues.subscriptionCount == 0, "upstream released once the count hits zero")
    }

    @Test("concurrent reads during attach/detach never observe a negative count")
    func concurrentReadsNeverNegative() async {
        let state = MutableStateFlow(0)
        let sawNegative = Mutex(false)
        let stopReading = Mutex(false)

        // Bounded read loops (not open-ended spins): each reader hops to the
        // actor per read and exits by flag or iteration cap, whichever first.
        let readers = (0..<4).map { _ in
            Task {
                for _ in 0..<10_000 {
                    if stopReading.withLock({ $0 }) { break }
                    if await state.subscriptionCount < 0 {
                        sawNegative.withLock { $0 = true }
                    }
                    await Task.yield()
                }
            }
        }

        // Churn subscribers while the readers watch the count.
        for _ in 0..<50 {
            let subscriber = Task { await state.asFlow().collect { _ in } }
            await waitUntil { await state.subscriptionCount >= 1 }
            subscriber.cancel()
            await waitUntil { await state.subscriptionCount == 0 }
        }

        stopReading.withLock { $0 = true }
        for reader in readers { await reader.value }
        #expect(!sawNegative.withLock { $0 }, "the count must never underflow")
    }

    @Test("100-task attach/detach storm returns to zero with starts matching stops")
    func attachDetachStorm() async {
        let state = MutableStateFlow(0)
        let starts = Mutex(0)
        let stops = Mutex(0)
        let stormDone = Mutex(false)

        // A whileSubscribed-style supervisor: starts the upstream when it
        // observes the count leave zero, stops it when the count returns to
        // zero. Polling observes crossings; starts and stops must pair up.
        let supervisor = Task {
            while !stormDone.withLock({ $0 }) {
                await waitUntil(timeout: .milliseconds(200)) {
                    await state.subscriptionCount > 0 || stormDone.withLock { $0 }
                }
                guard !stormDone.withLock({ $0 }) else { break }
                if await state.subscriptionCount > 0 {
                    starts.withLock { $0 += 1 }
                    await waitUntil { await state.subscriptionCount == 0 }
                    stops.withLock { $0 += 1 }
                }
            }
        }

        // An anchor subscriber attached before the storm and detached after
        // it makes exactly one 0 -> N -> 0 crossing deterministic: the test
        // converges on the supervisor observing it instead of racing a fast
        // storm against the supervisor's first poll.
        let anchor = Task { await state.asFlow().collect { _ in } }
        await waitUntil { starts.withLock { $0 } >= 1 }
        #expect(starts.withLock { $0 } == 1, "the anchor's attach is the only crossing so far")

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    let subscriber = Task { await state.asFlow().collect { _ in } }
                    // Let the subscription register before detaching, so the
                    // storm exercises real attach/detach churn.
                    await waitUntil { await state.subscriptionCount >= 1 }
                    subscriber.cancel()
                    await subscriber.value
                }
            }
        }

        anchor.cancel()
        await anchor.value
        await waitUntil { await state.subscriptionCount == 0 }
        #expect(await state.subscriptionCount == 0, "the storm must fully unwind")

        await waitUntil { stops.withLock { $0 } == starts.withLock { $0 } }
        stormDone.withLock { $0 = true }
        await supervisor.value
        #expect(starts.withLock { $0 } == stops.withLock { $0 },
                "every observed 0 -> N crossing must pair with a return to zero")
        #expect(starts.withLock { $0 } >= 1, "the supervisor observed the anchor's crossing")
    }
}
