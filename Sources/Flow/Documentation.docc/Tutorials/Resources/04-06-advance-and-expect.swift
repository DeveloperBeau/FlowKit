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

        try await TestScope.run { scope in
            let tester = try await scope.test(
                queries.asFlow().debounce(for: .milliseconds(300), clock: clock)
            )
            try? await Task.sleep(nanoseconds: 10_000_000)

            await queries.emit("s")
            await clock.advance(by: .milliseconds(100))
            await queries.emit("sw")
            await clock.advance(by: .milliseconds(100))
            await queries.emit("swi")

            // Nothing yet — still inside the 300 ms silence window.
            await tester.expectNoValue(within: .milliseconds(50))

            // Advance past the debounce window. The clock wakes the sleeping
            // debounce task, which emits the last value ("swi").
            await clock.advance(by: .milliseconds(300))
            try await tester.expectValue("swi")

            // No further values — intermediate "s" and "sw" were suppressed.
        }
    }
}
