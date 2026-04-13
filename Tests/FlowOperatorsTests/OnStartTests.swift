import Testing
import FlowCore
import FlowTesting
import FlowSharedModels
@testable import FlowOperators

@Suite("onStart operator")
struct OnStartTests {
    @Test("onStart runs before the upstream flow begins")
    func runsBeforeUpstream() async throws {
        let log = Mutex<[String]>([])
        let flow = Flow<Int> { collector in
            log.withLock { $0.append("upstream") }
            await collector.emit(1)
        }
        try await flow.onStart {
            log.withLock { $0.append("onStart") }
        }.test { tester in
            try await tester.expectValue(1)
            try await tester.expectCompletion()
        }
        #expect(log.withLock { $0 } == ["onStart", "upstream"])
    }
}
