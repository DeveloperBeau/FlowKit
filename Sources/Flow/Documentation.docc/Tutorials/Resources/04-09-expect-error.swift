import Testing
import Flow
import FlowTesting

@Suite("SearchViewModel error paths")
struct SearchViewModelErrorTests {

    @Test("resultsFlow propagates network error")
    func propagatesNetworkError() async throws {
        let viewModel = SearchViewModel(
            repository: FailingProductRepository(error: .networkUnavailable)
        )

        // ThrowingFlow uses ThrowingFlowTester which adds expectError(_:).
        try await viewModel.resultsFlow.test { tester in
            await viewModel.updateQuery("anything")

            // Typed overload that works when the error type is Equatable.
            try await tester.expectError(SearchError.networkUnavailable)
        }
    }
}
