import Foundation
import Testing
import Flow
import FlowTesting
// MyApp is the app target that holds SearchViewModel and ProductRepository.
@testable import MyApp

// A simple fake repository that always succeeds with a canned result.
struct FakeProductRepository: ProductRepository {
    let products: [Product]

    func search(query: String) -> ThrowingFlow<[Product]> {
        ThrowingFlow(of: products)
    }
}

@MainActor
@Suite("SearchViewModel")
struct SearchViewModelTests {

    @Test("results flow emits search results")
    func resultsFlowEmitsResults() async throws {
        let products = [
            Product(id: UUID(), name: "Widget", price: 5),
            Product(id: UUID(), name: "Gadget", price: 9)
        ]
        let viewModel = SearchViewModel(repository: FakeProductRepository(products: products))

        try await viewModel.results.asFlow().probing { reader in
            // A StateFlow replays its current value to each new collector.
            try await reader.expectValue(.idle)

            // Drive the pipeline. This test uses the real clock, so it waits
            // for the 300 ms debounce. The next section removes that wait.
            viewModel.update(query: "widget")

            try await reader.expectValue(.loaded(products))
        }
    }
}
