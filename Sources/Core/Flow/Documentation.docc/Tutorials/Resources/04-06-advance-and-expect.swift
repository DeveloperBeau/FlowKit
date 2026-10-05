import Testing
import Flow
import FlowTesting
import FlowTestClock

@Suite("Debounce operator")
struct DebounceOperatorTests {

    @Test("collapses rapid inputs into a single emission")
    func collapsesRapidInputs() async throws {
        let clock = TestClock()
        let queries = MutableSharedFlow<String>(replay: 0)

        try await queries.asFlow()
            .debounce(for: .milliseconds(300), clock: clock)
            .probing { reader in
                try await queries.waitForSubscribers(1)

                await queries.emit("s")
                await clock.advance(by: .milliseconds(100))
                await queries.emit("sw")
                await clock.advance(by: .milliseconds(100))
                await queries.emit("swi")

                // Still inside the 300 ms silence window.
                try await clock.waitForSleepers(1)

                // Advance past the debounce window. The clock wakes the sleeping
                // debounce task, which emits the last value ("swi").
                await clock.advance(by: .milliseconds(300))

                // The first value read is "swi": the intermediate "s" and "sw"
                // were suppressed, or this read would have returned one of them.
                try await reader.expectValue("swi")
            }
    }
}
