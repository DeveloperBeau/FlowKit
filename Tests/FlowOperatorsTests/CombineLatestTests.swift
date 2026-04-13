import Testing
import FlowCore
import FlowHotStreams
import FlowTesting
@testable import FlowOperators

@Suite("combineLatest operator")
struct CombineLatestTests {
    @Test("combineLatest emits latest pair whenever either flow emits")
    func emitsOnEitherUpdate() async throws {
        let flow1 = MutableSharedFlow<Int>(replay: 0)
        let flow2 = MutableSharedFlow<String>(replay: 0)

        try await TestScope.run(timeout: .seconds(3)) { scope in
            let tester = try await scope.test(
                flow1.asFlow().combineLatest(flow2.asFlow())
            )

            try? await Task.sleep(nanoseconds: 30_000_000)

            // First pair emitted only after both flows have emitted
            await flow1.emit(1)
            await tester.expectNoValue(within: .milliseconds(50))

            await flow2.emit("a")
            let v1 = try await tester.awaitValue()
            #expect(v1.0 == 1 && v1.1 == "a")

            // Updating flow1 emits new pair with latest from flow2
            await flow1.emit(2)
            let v2 = try await tester.awaitValue()
            #expect(v2.0 == 2 && v2.1 == "a")

            // Updating flow2 emits new pair with latest from flow1
            await flow2.emit("b")
            let v3 = try await tester.awaitValue()
            #expect(v3.0 == 2 && v3.1 == "b")
        }
    }

    @Test("combineLatest with transform applies closure")
    func withTransform() async throws {
        let flow1 = Flow(of: 1, 2)
        let flow2 = Flow(of: 10, 20)
        try await flow1.combineLatest(flow2) { $0 + $1 }.test { tester in
            // At least the first combined pair should arrive
            let first = try await tester.awaitValue()
            #expect(first >= 11) // 1+10 or later combinations
        }
    }

    @Test("combineLatest with empty flow produces empty flow")
    func emptyFlow() async throws {
        let flow1 = Flow(of: 1, 2, 3)
        let flow2 = Flow<String>.empty
        try await flow1.combineLatest(flow2).test { tester in
            try await tester.expectCompletion()
        }
    }
}
