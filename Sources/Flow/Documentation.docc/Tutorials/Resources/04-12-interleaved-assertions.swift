import Testing
import Flow
import FlowTesting
import FlowTestClock

@Suite("Multiple flows in TestScope")
struct MultipleFlowsTests {

    @Test("raw query sees every keystroke; debounced sees only the last")
    func rawAndDebouncedAreIndependent() async throws {
        let clock = TestClock()
        let queries = MutableSharedFlow<String>(replay: 0)

        try await TestScope.run { scope in
            let rawTester       = try await scope.test(queries.asFlow())
            let debouncedTester = try await scope.test(
                queries.asFlow().debounce(for: .milliseconds(300), clock: clock)
            )
            try? await Task.sleep(nanoseconds: 10_000_000)

            await queries.emit("h")
            await clock.advance(by: .milliseconds(100))
            await queries.emit("he")
            await clock.advance(by: .milliseconds(100))
            await queries.emit("hel")

            // The raw flow receives all three keystrokes immediately.
            try await rawTester.expectValue("h")
            try await rawTester.expectValue("he")
            try await rawTester.expectValue("hel")

            // The debounced flow emits nothing yet.
            await debouncedTester.expectNoValue(within: .milliseconds(50))

            // Expire the debounce window.
            await clock.advance(by: .milliseconds(300))

            // The debounced flow emits only the final value.
            try await debouncedTester.expectValue("hel")
        }
    }
}
