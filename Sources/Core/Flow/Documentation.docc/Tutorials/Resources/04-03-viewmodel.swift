import Testing
import Flow
import FlowTesting

// A simple fake repository that always succeeds with a canned result.
struct FakeProductRepository: ProductRepositoryProtocol {
    let results: [Product]

    func search(_ query: String) -> ThrowingFlow<[Product]> {
        ThrowingFlow(of: results)
    }
}

@Suite("SearchViewModel")
struct SearchViewModelTests {

    @Test("results flow emits search results")
    func resultsFlowEmitsResults() async throws {
        let fakeProducts = [Product(id: 1, name: "Widget"), Product(id: 2, name: "Gadget")]
        let viewModel = SearchViewModel(repository: FakeProductRepository(results: fakeProducts))

        try await viewModel.resultsFlow.test { tester in
            // Emit a query to drive the pipeline.
            await viewModel.queryFlow.emit("widget")

            let results = try await tester.awaitValue()
            #expect(results.count == 2)
            #expect(results.first?.name == "Widget")
        }
    }
}
