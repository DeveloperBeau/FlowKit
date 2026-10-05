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

        // A ThrowingFlow read through probing fails with expectError(_:matching:).
        try await viewModel.resultsFlow.probing { reader in
            await viewModel.updateQuery("anything")

            // The description names the expected error in a failure message.
            // SearchError is Equatable, so the match is a plain comparison.
            try await reader.expectError("network unavailable") { error in
                (error as? SearchError) == .networkUnavailable
            }
        }
    }
}
