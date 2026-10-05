import Testing
import FlowCore
import FlowSharedModels
import FlowTesting
import FlowTestSupport
@testable import FlowHotStreams

@Suite("Performance")
struct PerformanceTests {
    @Test("SharedFlow emit reaches 100 subscribers")
    func sharedFlowFanOut() async throws {
        let shared = MutableSharedFlow<Int>(replay: 0)

        try await ProbeScope.run { scope in
            var testers: [FlowReader<Int>] = []
            for _ in 0..<100 {
                testers.append(try await scope.probe(shared.asFlow()))
            }

            await pollUntil { await shared.subscriptionCount == 100 }

            await shared.emit(42)

            for tester in testers {
                try await tester.expectValue(42)
            }
        }
    }

    @Test("SharedFlow emit with 10 subscribers delivers every emission in order")
    func sharedFlowLatency() async throws {
        let shared = MutableSharedFlow<Int>(replay: 0)

        try await ProbeScope.run { scope in
            var testers: [FlowReader<Int>] = []
            for _ in 0..<10 {
                testers.append(try await scope.probe(shared.asFlow()))
            }

            await pollUntil { await shared.subscriptionCount == 10 }

            for i in 0..<10 {
                await shared.emit(i)
            }

            for tester in testers {
                for i in 0..<10 {
                    try await tester.expectValue(i)
                }
            }
        }
    }
}
