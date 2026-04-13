import Testing
import Flow
import FlowTesting
import FlowTestClock

@Suite("Multiple flows in TestScope")
struct MultipleFlowsTests {

    @Test("raw query and debounced query are independent")
    func rawAndDebouncedAreIndependent() async throws {
        let clock = TestClock()
        let queries = MutableSharedFlow<String>(replay: 0)
        let rawFlow = queries.asFlow()
        let debouncedFlow = queries.asFlow().debounce(for: .milliseconds(300), clock: clock)

        try await TestScope.run { scope in
            // Both flows are collected concurrently — each gets its own background task.
            let rawTester      = try await scope.test(rawFlow)
            let debouncedTester = try await scope.test(debouncedFlow)

            try? await Task.sleep(nanoseconds: 10_000_000)

            await queries.emit("h")
            await clock.advance(by: .milliseconds(100))
            await queries.emit("he")
            await clock.advance(by: .milliseconds(100))
            await queries.emit("hel")

            // Assertions against both testers continue in the next step.
            _ = rawTester
            _ = debouncedTester
        }
    }
}
