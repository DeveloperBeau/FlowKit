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

        try await viewModel.resultsFlow.probing { reader in
            // Wait until the pipeline is collecting the query flow.
            try await viewModel.queryFlow.waitForSubscribers(1)

            // Rapid typing, each keystroke resets the debounce timer.
            await viewModel.updateQuery("S")
            await clock.advance(by: .milliseconds(100))
            await viewModel.updateQuery("Sw")
            await clock.advance(by: .milliseconds(100))
            await viewModel.updateQuery("Swift")

            // Still inside the window, so the debounce is parked on its timer.
            try await clock.waitForSleepers(1)

            // Expire the window. The pipeline fires a single search.
            await clock.advance(by: .milliseconds(300))
            let results = try await reader.awaitValue()
            #expect(results.count == 1)
            #expect(results.first?.name == "Swift")
        }
    }
}
