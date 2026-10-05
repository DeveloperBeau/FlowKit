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
        try await viewModel.resultsFlow.probing { reader in
            await viewModel.updateQuery("anything")
            try await reader.expectError("network unavailable") { error in
                (error as? SearchError) == .networkUnavailable
            }
        }
    }

    @Test("resultsFlow propagates invalid-query error with its payload")
    func propagatesInvalidQueryError() async throws {
        let viewModel = SearchViewModel(
            repository: FailingProductRepository(error: .invalidQuery("!!"))
        )
        try await viewModel.resultsFlow.probing { reader in
            await viewModel.updateQuery("!!")

            // The matcher can inspect associated values, which is useful
            // when the error is not Equatable.
            try await reader.expectError("invalid query error") { error in
                guard case SearchError.invalidQuery(let q) = error else { return false }
                return q == "!!"
            }
        }
    }
}
