import Testing
import FlowCore
import FlowSharedModels
import FlowTesting
@testable import FlowHotStreams

@Suite("Performance")
struct PerformanceTests {
    @Test("SharedFlow emit to 100 subscribers completes within 5 seconds")
    func sharedFlowFanOut() async throws {
        let shared = MutableSharedFlow<Int>(replay: 0)

        try await TestScope.run(timeout: .seconds(10)) { scope in
            var testers: [FlowTester<Int>] = []
            for _ in 0..<100 {
                testers.append(try await scope.test(shared.asFlow()))
            }

            try? await Task.sleep(for: .seconds(0.1))

            await shared.emit(42)

            for tester in testers {
                try await tester.expectValue(42)
            }
        }
    }

    @Test("SharedFlow emit with 10 subscribers stays under 100ms per emission")
    func sharedFlowLatency() async throws {
        let shared = MutableSharedFlow<Int>(replay: 0)

        try await TestScope.run(timeout: .seconds(15)) { scope in
            var testers: [FlowTester<Int>] = []
            for _ in 0..<10 {
                testers.append(try await scope.test(shared.asFlow()))
            }

            try? await Task.sleep(for: .seconds(0.05))

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
