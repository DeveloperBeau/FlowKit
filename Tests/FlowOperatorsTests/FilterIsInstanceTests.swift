import Testing
import FlowCore
import FlowTesting
import FlowOperators

private protocol Event: Sendable {}
private struct LocationEvent: Event, Equatable { let id: Int }
private struct ChatEvent: Event, Equatable { let text: String }
private struct PresenceEvent: Event, Equatable {}

@Suite("filterIsInstance")
struct FilterIsInstanceTests {
    private var mixed: Flow<any Event> {
        Flow(of:
            LocationEvent(id: 1),
            ChatEvent(text: "a"),
            LocationEvent(id: 2),
            PresenceEvent(),
            ChatEvent(text: "b"),
            LocationEvent(id: 3)
        )
    }

    @Test("keeps only the requested type, in upstream order")
    func demuxesByType() async {
        let locations = await mixed.filterIsInstance(LocationEvent.self).toArray()
        #expect(locations == [LocationEvent(id: 1), LocationEvent(id: 2), LocationEvent(id: 3)])

        let chats = await mixed.filterIsInstance(ChatEvent.self).toArray()
        #expect(chats == [ChatEvent(text: "a"), ChatEvent(text: "b")])
    }

    @Test("the type argument can be inferred from context")
    func typeInference() async {
        let inferred: Flow<PresenceEvent> = mixed.filterIsInstance()
        #expect(await inferred.toArray() == [PresenceEvent()])
    }

    @Test("a stream with no matching elements yields an empty flow")
    func noMatchesYieldsEmpty() async {
        struct Unrelated: Sendable, Equatable {}
        #expect(await mixed.filterIsInstance(Unrelated.self).toArray().isEmpty)
    }

    @Test("ThrowingFlow variant filters values and propagates the error")
    func throwingVariant() async throws {
        struct Bad: Error, Equatable {}
        let source = ThrowingFlow<any Event> { collector in
            try await collector.emit(LocationEvent(id: 1))
            try await collector.emit(ChatEvent(text: "x"))
            try await collector.emit(LocationEvent(id: 2))
            throw Bad()
        }
        try await TestScope.run { scope in
            let tester = try await scope.test(source.filterIsInstance(LocationEvent.self))
            try await tester.expectValue(LocationEvent(id: 1))
            try await tester.expectValue(LocationEvent(id: 2))
            try await tester.expectError(Bad())
        }
    }
}
