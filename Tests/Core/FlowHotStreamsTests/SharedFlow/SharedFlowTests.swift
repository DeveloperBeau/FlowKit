import Testing
import Foundation
import FlowCore
import FlowSharedModels
import FlowTesting
import FlowTestSupport
@testable import FlowHotStreams

@Suite("MutableSharedFlow")
struct MutableSharedFlowTests {
    @Test("emit delivers to all subscribers")
    func emitDelivers() async throws {
        let shared = MutableSharedFlow<String>(replay: 0)
        try await ProbeScope.run { scope in
            let t1 = scope.probe(shared.asFlow())
            let t2 = scope.probe(shared.asFlow())

            await pollUntil { await shared.subscriptionCount == 2 }

            await shared.emit("event1")
            try await t1.expectValue("event1")
            try await t2.expectValue("event1")

            await shared.emit("event2")
            try await t1.expectValue("event2")
            try await t2.expectValue("event2")
        }
    }

    @Test("replay buffer replays to new subscribers")
    func replayBuffer() async throws {
        let shared = MutableSharedFlow<Int>(replay: 2)

        await shared.emit(1)
        await shared.emit(2)
        await shared.emit(3)

        try await shared.asFlow().probing { tester in
            try await tester.expectValue(2)
            try await tester.expectValue(3)
            // Nothing beyond the replay cache: the next value is the live one.
            await pollUntil { await shared.subscriptionCount == 1 }
            await shared.emit(4)
            try await tester.expectNextValue(4)
        }
    }

    @Test("subscriptionCount reflects active subscribers")
    func subscriptionCount() async throws {
        let shared = MutableSharedFlow<Int>(replay: 0)
        #expect(await shared.subscriptionCount == 0)
        try await ProbeScope.run { scope in
            _ = scope.probe(shared.asFlow())
            _ = scope.probe(shared.asFlow())
            await pollUntil { await shared.subscriptionCount == 2 }
            #expect(await shared.subscriptionCount == 2)
        }
    }

    @Test("resetReplayCache clears the buffer")
    func resetReplayCache() async throws {
        let shared = MutableSharedFlow<Int>(replay: 2)
        await shared.emit(1)
        await shared.emit(2)
        await shared.resetReplayCache()

        try await shared.asFlow().probing { tester in
            // An empty cache replays nothing: the first value is the live one.
            await pollUntil { await shared.subscriptionCount == 1 }
            await shared.emit(3)
            try await tester.expectNextValue(3)
        }
    }

    @Test("emit with zero replay does not buffer")
    func noReplayBuffer() async throws {
        let shared = MutableSharedFlow<Int>(replay: 0)
        await shared.emit(1)
        await shared.emit(2)

        try await shared.asFlow().probing { tester in
            // Zero replay buffers nothing: the first value is the live one.
            await pollUntil { await shared.subscriptionCount == 1 }
            await shared.emit(3)
            try await tester.expectNextValue(3)
        }
    }
}
