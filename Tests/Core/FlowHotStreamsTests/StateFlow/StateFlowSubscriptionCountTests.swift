import Testing
import FlowCore
import FlowSharedModels
import FlowTesting
import FlowTestSupport
@testable import FlowHotStreams

@Suite("MutableStateFlow.subscriptionCount")
struct StateFlowSubscriptionCountTests {
    @Test("count transitions 0 -> 1 -> 2 -> 1 -> 0 and gates an upstream collection")
    func countTransitionsAndGatesUpstream() async throws {
        let state = MutableStateFlow(0)
        #expect(await state.subscriptionCount == 0)

        // The whileSubscribed convention: the owner collects its upstream
        // use-case flow only while the UI observes the state.
        let upstreamValues = MutableSharedFlow<Int>(replay: 0)
        let upstreamActive = Signal()
        let upstreamDelivered = Signal()
        var upstream: Task<Void, Never>?

        let first = Task { await state.asFlow().collect { _ in } }
        try await state.waitForSubscribers(1)
        #expect(await state.subscriptionCount == 1)

        // First subscriber: start collecting the upstream into the state.
        upstream = Task {
            upstreamActive.fire()
            await upstreamValues.asFlow().collect { value in
                state.send(value)
                upstreamDelivered.fire()
            }
        }
        await upstreamActive.wait()
        try await upstreamValues.waitForSubscribers(1)
        await upstreamValues.emit(7)
        await upstreamDelivered.wait()
        #expect(state.value == 7, "upstream flows into the state while subscribed")

        let second = Task { await state.asFlow().collect { _ in } }
        try await state.waitForSubscribers(2)
        #expect(await state.subscriptionCount == 2)

        second.cancel()
        try await state.waitForSubscribers(atMost: 1)
        #expect(await state.subscriptionCount == 1)

        first.cancel()
        try await state.waitForSubscribers(atMost: 0)
        #expect(await state.subscriptionCount == 0)

        // Zero subscribers: the gate stops the upstream collection.
        upstream?.cancel()
        try await upstreamValues.waitForSubscribers(atMost: 0)
        #expect(await upstreamValues.subscriptionCount == 0, "upstream released once the count hits zero")
    }

    @Test("concurrent reads during attach/detach never observe a negative count")
    func concurrentReadsNeverNegative() async throws {
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
            try await state.waitForSubscribers(1)
            subscriber.cancel()
            try await state.waitForSubscribers(atMost: 0)
        }

        stopReading.withLock { $0 = true }
        for reader in readers { await reader.value }
        #expect(!sawNegative.withLock { $0 }, "the count must never underflow")
    }

    @Test("100-task attach/detach storm returns to zero with starts matching stops")
    func attachDetachStorm() async throws {
        let state = MutableStateFlow(0)
        let events = Recorder<String>()

        // A whileSubscribed-style supervisor: starts the upstream when the
        // count leaves zero, stops it when the count returns to zero. The
        // waiters observe crossings; starts and stops must pair up.
        let supervisor = Task {
            do {
                while true {
                    try await state.waitForSubscribers(1)
                    events.record("start")
                    try await state.waitForSubscribers(atMost: 0)
                    events.record("stop")
                }
            } catch {}
        }

        // An anchor subscriber attached before the storm and detached after
        // it makes exactly one 0 -> N -> 0 crossing deterministic.
        let anchor = Task { await state.asFlow().collect { _ in } }
        await events.wait(atLeast: 1)
        #expect(events.elements == ["start"], "the anchor's attach is the only crossing so far")

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    let subscriber = Task { await state.asFlow().collect { _ in } }
                    // Let the subscription register before detaching, so the
                    // storm exercises real attach/detach churn.
                    try await state.waitForSubscribers(1)
                    subscriber.cancel()
                    await subscriber.value
                }
            }
            try await group.waitForAll()
        }

        anchor.cancel()
        await anchor.value
        try await state.waitForSubscribers(atMost: 0)
        #expect(await state.subscriptionCount == 0, "the storm must fully unwind")

        await events.wait(atLeast: 2)
        supervisor.cancel()
        await supervisor.value
        #expect(events.elements == ["start", "stop"],
                "every observed 0 -> N crossing must pair with a return to zero")
    }
}
