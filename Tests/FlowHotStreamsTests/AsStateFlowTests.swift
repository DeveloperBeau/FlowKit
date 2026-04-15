import Testing
import FlowCore
import FlowSharedModels
import FlowTesting
@testable import FlowHotStreams

@Suite("Flow.asStateFlow")
struct AsStateFlowTests {
    @Test("asStateFlow exposes initial value before upstream emits")
    func initialValueVisible() async throws {
        let upstream = Flow<Int> { collector in
            try? await Task.sleep(for: .seconds(0.1))
            await collector.emit(42)
        }

        let stateFlow = upstream.asStateFlow(
            initialValue: 0,
            strategy: .lazy
        )

        try await stateFlow.asFlow().test { tester in
            try await tester.expectValue(0)
            try await tester.expectValue(42)
        }
    }

    @Test("asStateFlow with .eager starts upstream immediately")
    func eagerStartsUpstream() async throws {
        let upstream = Flow<String> { collector in
            await collector.emit("eager-emit")
        }
        let stateFlow = upstream.asStateFlow(
            initialValue: "initial",
            strategy: .eager
        )

        try? await Task.sleep(for: .seconds(0.05))
        #expect(await stateFlow.value == "eager-emit")
    }
}
