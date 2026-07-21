import Testing
import FlowCore
import FlowSharedModels
import FlowTesting
@testable import FlowHotStreams

@Suite("Read-only hot stream views")
struct ReadOnlyViewTests {
    // MARK: - asStateFlow()

    @Test("state view reflects every send, including replay to late subscribers")
    func stateViewReflectsSends() async throws {
        let source = MutableStateFlow(0)
        let view = source.asStateFlow()

        #expect(await view.value == 0)

        await source.send(1)
        #expect(await view.value == 1)

        // A late subscriber on the view replays the current value.
        try await view.asFlow().test { tester in
            try await tester.expectValue(1)
            await source.send(2)
            try await tester.expectValue(2)
        }
        #expect(await view.value == 2)
    }

    @Test("state view cannot be cast back to its mutable source")
    func stateViewHidesMutation() async {
        let source = MutableStateFlow(0)
        let view = source.asStateFlow()
        // The compile-time surface (`any StateFlow`) has no send/update; the
        // wrapper also blocks recovering the mutable type at runtime.
        #expect(!(view is MutableStateFlow<Int>))
    }

    @Test("state view subscribers converge on the final value under a send storm")
    func stateViewSendStorm() async {
        let source = MutableStateFlow(0)
        let view = source.asStateFlow()

        let latestA = Mutex<Int?>(nil)
        let latestB = Mutex<Int?>(nil)
        let subscriberA = Task {
            await view.asFlow().collect { value in latestA.withLock { $0 = value } }
        }
        let subscriberB = Task {
            await view.asFlow().collect { value in latestB.withLock { $0 = value } }
        }
        // Both subscribers observe the seed before the storm so neither races
        // its own subscription against the sends.
        await waitUntil { latestA.withLock { $0 } != nil && latestB.withLock { $0 } != nil }

        await withTaskGroup(of: Void.self) { group in
            for value in 1...100 {
                group.addTask { await source.send(value) }
            }
        }
        // Deterministic final value after the storm quiesces.
        await source.send(-1)

        await waitUntil { latestA.withLock { $0 } == -1 && latestB.withLock { $0 } == -1 }
        #expect(latestA.withLock { $0 } == -1)
        #expect(latestB.withLock { $0 } == -1)
        #expect(await view.value == -1)

        subscriberA.cancel()
        subscriberB.cancel()
    }

    // MARK: - asSharedFlow()

    @Test("shared view forwards emissions and replay to subscribers")
    func sharedViewForwardsEmissions() async throws {
        let source = MutableSharedFlow<String>(replay: 1)
        await source.emit("replayed")
        let view = source.asSharedFlow()

        try await view.asFlow().test { tester in
            try await tester.expectValue("replayed")
            await source.emit("live")
            try await tester.expectValue("live")
        }
    }

    @Test("shared view exposes the source's subscription count")
    func sharedViewSubscriptionCount() async {
        let source = MutableSharedFlow<Int>()
        let view = source.asSharedFlow()
        #expect(await view.subscriptionCount == 0)

        let subscriber = Task {
            await view.asFlow().collect { _ in }
        }
        await waitUntil { await view.subscriptionCount == 1 }
        #expect(await view.subscriptionCount == 1)
        #expect(await source.subscriptionCount == 1)

        subscriber.cancel()
        await waitUntil { await view.subscriptionCount == 0 }
        #expect(await view.subscriptionCount == 0)
    }

    @Test("shared view cannot be cast back to its mutable source")
    func sharedViewHidesMutation() async {
        let source = MutableSharedFlow<Int>()
        let view = source.asSharedFlow()
        #expect(!(view is MutableSharedFlow<Int>))
    }
}
