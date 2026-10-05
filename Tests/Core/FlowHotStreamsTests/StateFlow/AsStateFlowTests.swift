import Testing
import FlowCore
import FlowSharedModels
import FlowTesting
import FlowTestSupport
@testable import FlowHotStreams

@Suite("Flow.asStateFlow")
struct AsStateFlowTests {
    @Test("asStateFlow exposes initial value before upstream emits")
    func initialValueVisible() async throws {
        let sawInitial = Signal()
        let upstream = Flow<Int> { collector in
            // Held back until the test has read the initial value.
            await sawInitial.wait()
            await collector.emit(42)
        }

        let stateFlow = upstream.asStateFlow(
            initialValue: 0,
            strategy: .lazy
        )

        try await stateFlow.asFlow().probing { tester in
            try await tester.expectValue(0)
            sawInitial.fire()
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

        await pollUntil { stateFlow.value == "eager-emit" }
        #expect(stateFlow.value == "eager-emit")
    }
}
