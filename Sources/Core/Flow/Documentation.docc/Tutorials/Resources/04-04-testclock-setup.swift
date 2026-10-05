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

        // probing collects the flow in a background task, so advance() calls
        // interleave with the debounce sleeps. Reads wait on the flow itself.
        try await queries.asFlow()
            .debounce(for: .milliseconds(300), clock: clock)
            .probing { reader in
                // A hot flow with no replay drops anything emitted before the
                // collector attaches, so wait for the subscription first.
                try await queries.waitForSubscribers(1)

                // Assertions continue in the next steps...
                _ = reader
            }
    }
}
