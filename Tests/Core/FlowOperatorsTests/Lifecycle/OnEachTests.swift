import Testing
import FlowCore
import FlowTesting
import FlowSharedModels
@testable import FlowOperators

@Suite("onEach operator")
struct OnEachTests {
    @Test("onEach runs side-effect for each value without transforming")
    func runsForEachValue() async throws {
        let observed = Mutex<[Int]>([])
        let flow = Flow(of: 10, 20, 30)
        try await flow.onEach { value in
            observed.withLock { $0.append(value) }
        }.test { tester in
            try await tester.expectValue(10)
            try await tester.expectValue(20)
            try await tester.expectValue(30)
            try await tester.expectCompletion()
        }
        #expect(observed.withLock { $0 } == [10, 20, 30])
    }
}
