import Testing
import Flow

@Suite("ThrowingFlow first public API reachability")
struct ThrowingFlowFirstReachabilityTests {
    private struct Failure: Error, Equatable {}

    @Test("first on a ThrowingFlow is reachable and returns the first value")
    func firstReachable() async throws {
        let flow = ThrowingFlow(of: "a", "b")
        #expect(try await flow.first() == "a")
    }

    @Test("first(where:) on a ThrowingFlow is reachable and returns the first match")
    func firstWhereReachable() async throws {
        let flow = ThrowingFlow(of: 1, 2, 3)
        #expect(try await flow.first(where: { $0 > 1 }) == 2)
    }

    @Test("first on a ThrowingFlow that fails rethrows the error through the umbrella module")
    func firstRethrows() async {
        let flow = ThrowingFlow<Int> { _ in throw Failure() }
        await #expect(throws: Failure()) { try await flow.first() }
    }
}
