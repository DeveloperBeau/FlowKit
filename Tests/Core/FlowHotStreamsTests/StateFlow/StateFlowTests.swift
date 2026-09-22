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
        #expect(state.value == 42)
    }

    @Test("send updates the value")
    func sendUpdates() async {
        let state = MutableStateFlow(0)
        state.send(10)
        #expect(state.value == 10)
    }

    @Test("send with equal value is a no-op (deduplication)")
    func sendEqualDeduplicates() async throws {
        let state = MutableStateFlow(5)
        try await state.asFlow().test { tester in
            try await tester.expectValue(5)
            state.send(5)
            await tester.expectNoValue(within: .milliseconds(100))
            state.send(10)
            try await tester.expectValue(10)
        }
    }

    @Test("update transforms the current value atomically")
    func updateTransforms() async {
        let state = MutableStateFlow(10)
        state.update { $0 * 2 }
        #expect(state.value == 20)
    }

    @Test("new subscribers receive the current value immediately")
    func replayCurrentValue() async throws {
        let state = MutableStateFlow("initial")
        state.send("updated")
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

            state.send(1)
            try await t1.expectValue(1)
            try await t2.expectValue(1)

            state.send(2)
            try await t1.expectValue(2)
            try await t2.expectValue(2)
        }
    }
}
