import Testing
import Foundation
import FlowCore
import FlowSharedModels
import FlowTesting
@testable import FlowHotStreams

@Suite("MutableSharedFlow")
struct MutableSharedFlowTests {
    @Test("emit delivers to all subscribers")
    func emitDelivers() async throws {
        let shared = MutableSharedFlow<String>(replay: 0)
        try await TestScope.run { scope in
            let t1 = try await scope.test(shared.asFlow())
            let t2 = try await scope.test(shared.asFlow())

            try? await Task.sleep(nanoseconds: 20_000_000)

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

        try await shared.asFlow().test { tester in
            try await tester.expectValue(2)
            try await tester.expectValue(3)
            await tester.expectNoValue(within: .milliseconds(50))
        }
    }

    @Test("subscriptionCount reflects active subscribers")
    func subscriptionCount() async throws {
        let shared = MutableSharedFlow<Int>(replay: 0)
        #expect(await shared.subscriptionCount == 0)
        try await TestScope.run { scope in
            _ = try await scope.test(shared.asFlow())
            _ = try await scope.test(shared.asFlow())
            try? await Task.sleep(nanoseconds: 20_000_000)
            #expect(await shared.subscriptionCount == 2)
        }
    }

    @Test("resetReplayCache clears the buffer")
    func resetReplayCache() async throws {
        let shared = MutableSharedFlow<Int>(replay: 2)
        await shared.emit(1)
        await shared.emit(2)
        await shared.resetReplayCache()

        try await shared.asFlow().test { tester in
            await tester.expectNoValue(within: .milliseconds(100))
        }
    }

    @Test("emit with zero replay does not buffer")
    func noReplayBuffer() async throws {
        let shared = MutableSharedFlow<Int>(replay: 0)
        await shared.emit(1)
        await shared.emit(2)

        try await shared.asFlow().test { tester in
            await tester.expectNoValue(within: .milliseconds(100))
        }
    }
}
