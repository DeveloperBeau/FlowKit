import Testing
import FlowCore
import FlowTesting
import FlowTestSupport
@testable import FlowHotStreams

/// How long a helper waits for values that a broken subscription never
/// delivers. A correct subscription never reaches it.
private let safetyNet: Duration = .seconds(30)

/// Collects `flow` until `condition` holds for the values so far, then cancels
/// the collection and returns everything that arrived.
///
/// When the values never arrive, the safety net ends the wait and the short
/// result fails the caller's comparison.
private func values<Element: Sendable>(
    from flow: Flow<Element>,
    until condition: @escaping @Sendable ([Element]) -> Bool
) async -> [Element] {
    let received = Recorder<Element>()
    let collecting = Task { await flow.collect { received.record($0) } }
    _ = try? await withThrowingTimeout(safetyNet, clock: ContinuousClock()) {
        await received.wait(until: condition)
    }
    collecting.cancel()
    await collecting.value
    return received.elements
}

private func values<Element: Sendable>(_ count: Int, from flow: Flow<Element>) async -> [Element] {
    await values(from: flow) { $0.count >= count }
}

/// Collects `flow` to its end. Returns `nil` when the collection does not end.
private func valuesToCompletion<Element: Sendable>(of flow: Flow<Element>) async -> [Element]? {
    let received = Recorder<Element>()
    let collecting = Task { await flow.collect { received.record($0) } }
    let hasCompleted = try? await withThrowingTimeout(safetyNet, clock: ContinuousClock()) {
        await withTaskCancellationHandler {
            await collecting.value
        } onCancel: {
            collecting.cancel()
        }
        return !Task.isCancelled
    }
    collecting.cancel()
    await collecting.value
    return hasCompleted == true ? received.elements : nil
}

/// Registers from synchronous code, which cannot await a collector.
private func registerSynchronously(on shared: MutableSharedFlow<Int>) -> Flow<Int> {
    shared.subscribed()
}

@MainActor
private func registerOnMainActor(on shared: MutableSharedFlow<Int>) -> Flow<Int> {
    shared.subscribed()
}

/// A seeded generator, so a failing fuzz run can be repeated from its seed.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

@Suite("MutableSharedFlow.subscribed")
struct SharedFlowSubscribedTests {
    @Test("values emitted between subscribed() and collect arrive in order")
    func deliversValuesEmittedBeforeCollection() async {
        let shared = MutableSharedFlow<Int>()
        let incoming = shared.subscribed()

        await shared.emit(1)
        await shared.emit(2)
        await shared.emit(3)

        #expect(await values(3, from: incoming) == [1, 2, 3])
    }

    @Test("a value emitted before subscribed() is not delivered without replay")
    func skipsValuesEmittedBeforeRegistration() async {
        let shared = MutableSharedFlow<Int>()
        await shared.emit(1)
        let incoming = shared.subscribed()
        await shared.emit(2)

        #expect(await values(1, from: incoming) == [2])
    }

    @Test("the subscriber is counted when subscribed() returns")
    func countsSubscriberAtRegistration() async {
        let shared = MutableSharedFlow<Int>()
        let incoming = shared.subscribed()

        #expect(await shared.subscriptionCount == 1)
        withExtendedLifetime(incoming) {}
    }

    @Test("dropping the flow without collecting removes the subscriber")
    func droppedSubscriptionIsRemoved() async {
        let shared = MutableSharedFlow<Int>()
        do {
            let incoming = shared.subscribed()
            #expect(await shared.subscriptionCount == 1)
            withExtendedLifetime(incoming) {}
        }

        #expect(await shared.subscriptionCount == 0)
        // Emitting to a flow with a removed registration is harmless.
        await shared.emit(1)
        #expect(await shared.subscriptionCount == 0)
    }

    @Test("dropping the flow resumes a waiter for no subscribers")
    func droppedSubscriptionResumesCountWaiter() async {
        let shared = MutableSharedFlow<Int>()
        var incoming: Flow<Int>? = shared.subscribed()
        let hasNoSubscribers = Signal()
        let waiting = Task {
            try await shared.waitForSubscribers(atMost: 0)
            hasNoSubscribers.fire()
        }
        #expect(await !hasNoSubscribers.firesWithinHops(), "the registration must hold the waiter")
        withExtendedLifetime(incoming) {}

        incoming = nil

        #expect(await hasNoSubscribers.fires())
        waiting.cancel()
    }

    @Test("subscribed() resumes a waiter for one subscriber")
    func registrationResumesCountWaiter() async {
        let shared = MutableSharedFlow<Int>()
        let hasSubscriber = Signal()
        let waiting = Task {
            try await shared.waitForSubscribers(1)
            hasSubscriber.fire()
        }
        #expect(await !hasSubscriber.firesWithinHops(), "no subscriber is attached yet")

        let incoming = shared.subscribed()

        #expect(await hasSubscriber.fires())
        withExtendedLifetime(incoming) {}
        waiting.cancel()
    }

    @Test("cancelling the collecting task removes the subscriber")
    func cancelledCollectorIsRemoved() async {
        let shared = MutableSharedFlow<Int>()
        let incoming = shared.subscribed()
        let received = Recorder<Int>()
        let collecting = Task { await incoming.collect { received.record($0) } }
        await shared.emit(1)
        _ = try? await withThrowingTimeout(safetyNet, clock: ContinuousClock()) {
            await received.wait(atLeast: 1)
        }
        #expect(received.elements == [1])
        #expect(await shared.subscriptionCount == 1)

        collecting.cancel()
        await collecting.value

        #expect(await shared.subscriptionCount == 0)
    }

    @Test("a task cancelled before it collects removes the subscriber")
    func collectorCancelledBeforeStartIsRemoved() async {
        let shared = MutableSharedFlow<Int>()
        let incoming = shared.subscribed()
        let mayStart = Signal()
        let collecting = Task {
            await mayStart.wait()
            await incoming.collect { _ in }
        }
        #expect(await shared.subscriptionCount == 1)

        collecting.cancel()
        await collecting.value

        #expect(await shared.subscriptionCount == 0)
    }

    @Test("an uncollected dropOldest subscription keeps only the newest values")
    func dropOldestBoundsUncollectedSubscription() async {
        let shared = MutableSharedFlow<Int>(extraBufferCapacity: 2, onBufferOverflow: .dropOldest)
        let incoming = shared.subscribed()
        for value in 1...5 { await shared.emit(value) }

        #expect(await values(2, from: incoming) == [4, 5])
    }

    @Test("an uncollected dropLatest subscription keeps only the oldest values")
    func dropLatestBoundsUncollectedSubscription() async {
        let shared = MutableSharedFlow<Int>(extraBufferCapacity: 2, onBufferOverflow: .dropLatest)
        let incoming = shared.subscribed()
        for value in 1...5 { await shared.emit(value) }

        let received = Recorder<Int>()
        let collecting = Task { await incoming.collect { received.record($0) } }
        _ = try? await withThrowingTimeout(safetyNet, clock: ContinuousClock()) {
            await received.wait(atLeast: 2)
        }
        // The buffer is empty again, so a value emitted now has room. It
        // arrives after everything the buffer kept.
        await shared.emit(99)
        _ = try? await withThrowingTimeout(safetyNet, clock: ContinuousClock()) {
            await received.wait { $0.last == 99 }
        }
        collecting.cancel()
        await collecting.value

        #expect(received.elements == [1, 2, 99])
    }

    @Test("an uncollected subscription with the default policy keeps every value")
    func defaultPolicyKeepsEveryValue() async {
        let shared = MutableSharedFlow<Int>()
        let incoming = shared.subscribed()
        for value in 1...10_000 { await shared.emit(value) }

        #expect(await values(10_000, from: incoming) == Array(1...10_000))
    }

    @Test("a second collection completes at once with no values")
    func secondCollectionCompletesAtOnce() async {
        let shared = MutableSharedFlow<Int>()
        let incoming = shared.subscribed()
        await shared.emit(1)
        #expect(await values(1, from: incoming) == [1])

        await shared.emit(2)

        #expect(await valuesToCompletion(of: incoming) == [])
    }

    @Test("a second collection during the first completes at once and takes no values")
    func concurrentSecondCollectionTakesNothing() async {
        let shared = MutableSharedFlow<Int>()
        let incoming = shared.subscribed()
        let received = Recorder<Int>()
        let first = Task { await incoming.collect { received.record($0) } }
        await shared.emit(1)
        _ = try? await withThrowingTimeout(safetyNet, clock: ContinuousClock()) {
            await received.wait(atLeast: 1)
        }

        #expect(await valuesToCompletion(of: incoming) == [])

        await shared.emit(2)
        _ = try? await withThrowingTimeout(safetyNet, clock: ContinuousClock()) {
            await received.wait(atLeast: 2)
        }
        #expect(received.elements == [1, 2])
        #expect(await shared.subscriptionCount == 1)
        first.cancel()
        await first.value
    }

    @Test("the replay at registration arrives before later values, with no repeat")
    func deliversReplayThenLaterValues() async {
        let shared = MutableSharedFlow<Int>(replay: 2)
        for value in 1...3 { await shared.emit(value) }
        let incoming = shared.subscribed()
        await shared.emit(4)
        await shared.emit(99)

        #expect(await values(from: incoming) { $0.last == 99 } == [2, 3, 4, 99])
    }

    @Test("the replay arrives when nothing is emitted after registration")
    func deliversReplayWithoutLaterValues() async {
        let shared = MutableSharedFlow<Int>(replay: 2)
        for value in 1...3 { await shared.emit(value) }
        let incoming = shared.subscribed()

        #expect(await values(2, from: incoming) == [2, 3])
    }

    @Test("values emitted after registration are not also replayed")
    func doesNotReplayValuesAlreadyDelivered() async {
        let shared = MutableSharedFlow<Int>(replay: 2)
        let incoming = shared.subscribed()
        await shared.emit(1)
        await shared.emit(2)
        await shared.emit(99)

        #expect(await values(from: incoming) { $0.last == 99 } == [1, 2, 99])
    }

    @Test("a registered subscriber and an asFlow() collector receive the same values")
    func coexistsWithLazyCollector() async throws {
        let shared = MutableSharedFlow<Int>()
        let incoming = shared.subscribed()
        let lazy = Recorder<Int>()
        let collecting = Task { await shared.asFlow().collect { lazy.record($0) } }
        try await withThrowingTimeout(safetyNet, clock: ContinuousClock()) {
            try await shared.waitForSubscribers(2)
        }

        await shared.emit(1)
        await shared.emit(2)

        #expect(await values(2, from: incoming) == [1, 2])
        _ = try? await withThrowingTimeout(safetyNet, clock: ContinuousClock()) {
            await lazy.wait(atLeast: 2)
        }
        #expect(lazy.elements == [1, 2])
        collecting.cancel()
        await collecting.value
        #expect(await shared.subscriptionCount == 0)
    }

    @Test("asFlow() still registers only when it is collected")
    func asFlowStaysLazy() async {
        let shared = MutableSharedFlow<Int>()
        let lazy = shared.asFlow()

        #expect(await shared.subscriptionCount == 0)
        withExtendedLifetime(lazy) {}
    }

    @Test("buffered values arrive and the collection ends after the flow is released")
    func completesAfterFlowIsReleased() async {
        let incoming: Flow<Int>
        do {
            let shared = MutableSharedFlow<Int>()
            incoming = shared.subscribed()
            await shared.emit(1)
            await shared.emit(2)
        }

        #expect(await valuesToCompletion(of: incoming) == [1, 2])
    }

    @Test("synchronous code registers a subscriber")
    func registersFromSynchronousCode() async {
        let shared = MutableSharedFlow<Int>()
        let incoming = registerSynchronously(on: shared)
        await shared.emit(7)

        #expect(await values(1, from: incoming) == [7])
    }

    @Test("main actor code registers a subscriber")
    func registersFromMainActor() async {
        let shared = MutableSharedFlow<Int>()
        let incoming = await registerOnMainActor(on: shared)
        await shared.emit(7)

        #expect(await values(1, from: incoming) == [7])
    }

    @Test("a subscriber registered during emission receives every value emitted after it returned")
    func concurrentRegistrationMissesNothingAfterItReturns() async {
        let shared = MutableSharedFlow<Int>()
        let last = 2_000
        let registrants = 16
        // The emitter announces each value before it emits it, so a count of
        // `n` announcements means that the emit of `n + 1` has not started.
        let announced = Recorder<Int>()
        let emitting = Task {
            for value in 1...last {
                announced.record(value)
                await shared.emit(value)
            }
        }

        let results = await withTaskGroup(of: (announcedBefore: Int, received: [Int]).self) { group in
            for registrant in 0..<registrants {
                group.addTask {
                    // Spread the registrations over the run of the emitter.
                    await announced.wait(atLeast: registrant * 100 + 1)
                    let incoming = shared.subscribed()
                    let announcedBefore = announced.count
                    return (announcedBefore, await values(from: incoming) { $0.last == -1 })
                }
            }
            await emitting.value
            // Every registration has returned once the count shows them all.
            _ = try? await withThrowingTimeout(safetyNet, clock: ContinuousClock()) {
                try await shared.waitForSubscribers(registrants)
            }
            await shared.emit(-1)
            var results: [(announcedBefore: Int, received: [Int])] = []
            for await result in group { results.append(result) }
            return results
        }

        #expect(results.count == registrants)
        for result in results {
            // A contiguous run up to the last value, then the sentinel.
            let numbered = Array(result.received.dropLast())
            let first = numbered.first ?? last + 1
            #expect(result.received.last == -1)
            #expect(numbered == Array(stride(from: first, through: last, by: 1)))
            #expect(
                first <= result.announcedBefore + 1,
                "value \(result.announcedBefore + 1) was emitted after subscribed() returned"
            )
        }
        #expect(await shared.subscriptionCount == 0)
    }

    @Test("random subscribe, emit, drop and collect steps match a model", arguments: 0..<40)
    func fuzzMatchesModel(run: Int) async {
        let seed = 0x5EED_0000 + UInt64(run)
        var generator = SeededGenerator(state: seed)
        let replay = Int.random(in: 0...3, using: &generator)
        let shared = MutableSharedFlow<Int>(replay: replay)
        var emitted: [Int] = []
        var live: [(flow: Flow<Int>, expected: [Int])] = []

        func emitNext() async {
            let value = emitted.count
            emitted.append(value)
            for index in live.indices { live[index].expected.append(value) }
            await shared.emit(value)
        }

        for step in 0..<60 {
            switch Int.random(in: 0..<4, using: &generator) {
            case 0:
                live.append((shared.subscribed(), Array(emitted.suffix(replay))))
            case 1:
                await emitNext()
            case 2 where !live.isEmpty:
                live.remove(at: Int.random(in: live.indices, using: &generator))
            case 3 where !live.isEmpty:
                // The value emitted here closes the expected list, so a
                // repeated or late value shows before it.
                await emitNext()
                let subscriber = live.remove(at: Int.random(in: live.indices, using: &generator))
                let closing = emitted.count - 1
                let received = await values(from: subscriber.flow) { $0.last == closing }
                #expect(received == subscriber.expected, "seed \(seed), step \(step), replay \(replay)")
            default:
                break
            }
            #expect(await shared.subscriptionCount == live.count, "seed \(seed), step \(step)")
        }
    }
}

@Suite("MutableStateFlow.subscribed")
struct StateFlowSubscribedTests {
    @Test("yields the value at registration, then every later change")
    func yieldsRegistrationValueThenChanges() async {
        let state = MutableStateFlow(0)
        let incoming = state.subscribed()

        state.send(1)
        state.send(2)

        #expect(await values(3, from: incoming) == [0, 1, 2])
    }

    @Test("a value set before registration is the first value")
    func startsFromValueSetBeforeRegistration() async {
        let state = MutableStateFlow(0)
        state.send(5)
        let incoming = state.subscribed()
        state.send(6)

        #expect(await values(2, from: incoming) == [5, 6])
    }

    @Test("setting an equal value yields nothing")
    func skipsEqualValue() async {
        let state = MutableStateFlow(1)
        let incoming = state.subscribed()
        state.send(1)
        state.send(2)

        #expect(await values(2, from: incoming) == [1, 2])
    }

    @Test("the subscriber is counted when subscribed() returns, and removed when dropped")
    func countsThenRemovesDroppedSubscription() async {
        let state = MutableStateFlow(0)
        do {
            let incoming = state.subscribed()
            #expect(await state.subscriptionCount == 1)
            withExtendedLifetime(incoming) {}
        }

        #expect(await state.subscriptionCount == 0)
        state.send(1)
        #expect(state.value == 1)
    }

    @Test("subscribed() resumes a waiter for one subscriber")
    func registrationResumesCountWaiter() async {
        let state = MutableStateFlow(0)
        let hasSubscriber = Signal()
        let waiting = Task {
            try await state.waitForSubscribers(1)
            hasSubscriber.fire()
        }
        #expect(await !hasSubscriber.firesWithinHops(), "no subscriber is attached yet")

        let incoming = state.subscribed()

        #expect(await hasSubscriber.fires())
        withExtendedLifetime(incoming) {}
        waiting.cancel()
    }

    @Test("cancelling the collecting task removes the subscriber")
    func cancelledCollectorIsRemoved() async {
        let state = MutableStateFlow(0)
        let incoming = state.subscribed()
        #expect(await state.subscriptionCount == 1)

        #expect(await values(1, from: incoming) == [0])

        #expect(await state.subscriptionCount == 0)
    }

    @Test("a second collection completes at once with no values")
    func secondCollectionCompletesAtOnce() async {
        let state = MutableStateFlow(0)
        let incoming = state.subscribed()
        #expect(await values(1, from: incoming) == [0])

        state.send(1)

        #expect(await valuesToCompletion(of: incoming) == [])
    }

    @Test("buffered changes arrive and the collection ends after the flow is released")
    func completesAfterFlowIsReleased() async {
        let incoming: Flow<Int>
        do {
            let state = MutableStateFlow(0)
            incoming = state.subscribed()
            state.send(1)
        }

        #expect(await valuesToCompletion(of: incoming) == [0, 1])
    }

    @Test("asFlow() still registers only when it is collected")
    func asFlowStaysLazy() async {
        let state = MutableStateFlow(0)
        let lazy = state.asFlow()

        #expect(await state.subscriptionCount == 0)
        withExtendedLifetime(lazy) {}
    }

    @Test("concurrent writers reach a registered subscriber in update order")
    func concurrentWritersArriveInOrder() async {
        let state = MutableStateFlow(0)
        let incoming = state.subscribed()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    for _ in 0..<100 { state.update { $0 + 1 } }
                }
            }
        }

        #expect(await values(from: incoming) { $0.last == 800 } == Array(0...800))
    }
}
