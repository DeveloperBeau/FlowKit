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

        try await TestScope.run { scope in
            let tester = try await scope.test(
                queries.asFlow().debounce(for: .milliseconds(300), clock: clock)
            )
            try? await Task.sleep(for: .seconds(0.01))

            // Simulate three rapid keystrokes 100 ms apart.
            await queries.emit("s")
            await clock.advance(by: .milliseconds(100))
            await queries.emit("sw")
            await clock.advance(by: .milliseconds(100))
            await queries.emit("swi")
            await clock.advance(by: .milliseconds(100))

            // 300 ms total elapsed, but the last keystroke reset the timer
            // 100 ms ago, so we are only 100 ms into the 300 ms window.
            // Nothing should have been emitted yet.
            await tester.expectNoValue(within: .milliseconds(50))
        }
    }
}
