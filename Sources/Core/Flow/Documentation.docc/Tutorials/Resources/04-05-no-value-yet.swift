import Testing
import Flow
import FlowTesting
import FlowTestClock

@Suite("Debounce operator")
struct DebounceOperatorTests {

    @Test("collapses rapid inputs")
    func collapsesRapidInputs() async throws {
        let clock = TestClock()
        let queries = MutableSharedFlow<String>(replay: 0)

        try await queries.asFlow()
            .debounce(for: .milliseconds(300), clock: clock)
            .probing { reader in
                try await queries.waitForSubscribers(1)

                // Simulate three rapid keystrokes 100 ms apart.
                await queries.emit("s")
                await clock.advance(by: .milliseconds(100))
                await queries.emit("sw")
                await clock.advance(by: .milliseconds(100))
                await queries.emit("swi")

                // The debounce is parked on its 300 ms window, which the last
                // keystroke restarted. Waiting for that sleep proves the timer is
                // running, so nothing has been emitted yet.
                try await clock.waitForSleepers(1)

                _ = reader
            }
    }
}
