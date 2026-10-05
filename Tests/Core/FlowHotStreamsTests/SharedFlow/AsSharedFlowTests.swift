import Testing
import FlowCore
import FlowSharedModels
import FlowTesting
import FlowTestSupport
@testable import FlowHotStreams

@Suite("Flow.asSharedFlow")
struct AsSharedFlowTests {
    @Test("asSharedFlow broadcasts upstream values to subscribers")
    func broadcasts() async throws {
        let subscribed = Signal()
        let upstream = Flow<String> { collector in
            // Held back until the subscriber is registered; replay is 0.
            await subscribed.wait()
            await collector.emit("first")
            await collector.emit("second")
        }

        let shared = upstream.asSharedFlow(
            replay: 0,
            strategy: .lazy
        )

        try await shared.asFlow().probing { tester in
            await pollUntil { await shared.subscriptionCount == 1 }
            subscribed.fire()
            try await tester.expectValue("first")
            try await tester.expectValue("second")
        }
    }
}
