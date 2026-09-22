import Testing
import Flow
import FlowTesting

@Suite("SearchViewModel error paths")
struct SearchViewModelErrorTests {

    @Test("resultsFlow propagates network error (typed)")
    func propagatesNetworkError() async throws {
        let viewModel = SearchViewModel(
            repository: FailingProductRepository(error: .networkUnavailable)
        )
        try await viewModel.resultsFlow.test { tester in
            await viewModel.updateQuery("anything")
            try await tester.expectError(SearchError.networkUnavailable)
        }
    }

    @Test("resultsFlow propagates invalid-query error (predicate)")
    func propagatesInvalidQueryError() async throws {
        let viewModel = SearchViewModel(
            repository: FailingProductRepository(error: .invalidQuery("!!"))
        )
        try await viewModel.resultsFlow.test { tester in
            await viewModel.updateQuery("!!")

            // Predicate overload, useful when the error has associated values
            // you want to inspect without requiring Equatable conformance.
            try await tester.expectError("invalid query error") { error in
                guard case SearchError.invalidQuery(let q) = error else { return false }
                return q == "!!"
            }
        }
    }
}
