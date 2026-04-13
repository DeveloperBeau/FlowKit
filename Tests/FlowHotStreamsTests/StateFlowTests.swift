import Testing
import FlowCore
import FlowTesting
import FlowSharedModels
@testable import FlowHotStreams

@Suite("MutableStateFlow")
struct MutableStateFlowTests {
    @Test("initial value is readable via .value")
    func initialValue() async {
        let state = MutableStateFlow(42)
        #expect(await state.value == 42)
    }

    @Test("send updates the value")
    func sendUpdates() async {
        let state = MutableStateFlow(0)
        await state.send(10)
        #expect(await state.value == 10)
    }

    @Test("send with equal value is a no-op (deduplication)")
    func sendEqualDeduplicates() async throws {
        let state = MutableStateFlow(5)
        try await state.asFlow().test { tester in
            try await tester.expectValue(5)
            await state.send(5)
            await tester.expectNoValue(within: .milliseconds(100))
            await state.send(10)
            try await tester.expectValue(10)
        }
    }

    @Test("update transforms the current value atomically")
    func updateTransforms() async {
        let state = MutableStateFlow(10)
        await state.update { $0 * 2 }
        #expect(await state.value == 20)
    }

    @Test("new subscribers receive the current value immediately")
    func replayCurrentValue() async throws {
        let state = MutableStateFlow("initial")
        await state.send("updated")
        try await state.asFlow().test { tester in
            try await tester.expectValue("updated")
        }
    }

    @Test("multiple subscribers all receive updates")
    func multipleSubscribers() async throws {
        let state = MutableStateFlow(0)
        try await TestScope.run { scope in
            let t1 = try await scope.test(state.asFlow())
            let t2 = try await scope.test(state.asFlow())

            try await t1.expectValue(0)
            try await t2.expectValue(0)

            await state.send(1)
            try await t1.expectValue(1)
            try await t2.expectValue(1)

            await state.send(2)
            try await t1.expectValue(2)
            try await t2.expectValue(2)
        }
    }
}
