import Foundation
import Testing
import Flow
import FlowTesting
// MyApp is the app target that holds SearchViewModel.
@testable import MyApp

@MainActor
@Suite("SearchViewModel with TestClock")
struct SearchViewModelClockTests {

    @Test("debounced pipeline emits once after window expires")
    func debouncedPipelineEmitsOnce() async throws {
        let clock = TestClock()
        let products = [Product(id: UUID(), name: "Swift", price: 10)]
        let viewModel = SearchViewModel(
            repository: FakeProductRepository(products: products),
            clock: clock
        )

        // Rapid typing. The query is a StateFlow, so only the latest value
        // survives. Set it before collecting, so the debounce timer that the
        // test waits for is the one for this query.
        viewModel.update(query: "S")
        viewModel.update(query: "Sw")
        viewModel.update(query: "Swift")

        try await viewModel.results.asFlow().probing { reader in
            // The first value is the StateFlow's initial state.
            try await reader.expectValue(.idle)

            // The debounce is parked on its timer. Expire the window, and
            // the pipeline fires a single search.
            try await clock.waitForSleepers(1)
            await clock.advance(by: .milliseconds(300))

            try await reader.expectValue(.loaded(products))
        }
    }
}
