import Testing
import FlowCore
import FlowSharedModels
import FlowTesting
@testable import FlowHotStreams

@Suite("Flow.asSharedFlow")
struct AsSharedFlowTests {
    @Test("asSharedFlow broadcasts upstream values to subscribers")
    func broadcasts() async throws {
        let upstream = Flow<String> { collector in
            try? await Task.sleep(for: .seconds(0.02))
            await collector.emit("first")
            await collector.emit("second")
        }

        let shared = upstream.asSharedFlow(
            replay: 0,
            strategy: .lazy
        )

        try await shared.asFlow().test { tester in
            try await tester.expectValue("first")
            try await tester.expectValue("second")
        }
    }
}
