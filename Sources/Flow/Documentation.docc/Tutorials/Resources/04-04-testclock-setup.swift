import Testing
import Flow
import FlowTesting
import FlowTestClock

@Suite("Debounce operator")
struct DebounceOperatorTests {

    @Test("collapses rapid inputs")
    func collapsesRapidInputs() async throws {
        // TestClock starts at virtual time zero. Calling advance(by:) moves
        // the clock forward without any real time passing.
        let clock = TestClock()
        let queries = MutableSharedFlow<String>(replay: 0)

        // TestScope.run collects the flow in a concurrent background task so
        // that advance() calls interleave correctly with the debounce sleeps.
        try await TestScope.run { scope in
            let tester = try await scope.test(
                queries.asFlow().debounce(for: .milliseconds(300), clock: clock)
            )

            // Small real-time yield lets the collection task attach before we emit.
            try? await Task.sleep(nanoseconds: 10_000_000)

            // Assertions continue in the next steps...
            _ = tester
        }
    }
}
