import Testing
import Flow
import FlowTesting
import FlowTestClock

@Suite("SearchViewModel with TestClock")
struct SearchViewModelClockTests {

    @Test("debounced pipeline emits once after window expires")
    func debouncedPipelineEmitsOnce() async throws {
        let clock = TestClock()
        let fakeProducts = [Product(id: 1, name: "Swift")]
        let viewModel = SearchViewModel(
            repository: FakeProductRepository(results: fakeProducts),
            clock: clock
        )

        try await TestScope.run { scope in
            let resultsTester = try await scope.test(viewModel.resultsFlow)
            try? await Task.sleep(nanoseconds: 10_000_000)

            // Rapid typing, each keystroke resets the debounce timer.
            await viewModel.updateQuery("S")
            await clock.advance(by: .milliseconds(100))
            await viewModel.updateQuery("Sw")
            await clock.advance(by: .milliseconds(100))
            await viewModel.updateQuery("Swift")

            // Still inside the window, so no results yet.
            await resultsTester.expectNoValue(within: .milliseconds(50))

            // Expire the window. The pipeline fires a single search.
            await clock.advance(by: .milliseconds(300))
            let results = try await resultsTester.awaitValue()
            #expect(results.count == 1)
            #expect(results.first?.name == "Swift")
        }
    }
}
