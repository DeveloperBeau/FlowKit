import Foundation
import Testing
import Flow
import FlowTesting
// MyApp is the app target that holds SearchViewModel and ProductRepository.
@testable import MyApp

@Suite("Repository error paths")
struct RepositoryErrorTests {

    @Test("search fails with a network error")
    func searchFailsWithNetworkError() async throws {
        let repository = FailingProductRepository(error: .networkUnavailable)
        try await repository.search(query: "anything").probing { reader in
            try await reader.expectError("network unavailable") { error in
                (error as? SearchError) == .networkUnavailable
            }
        }
    }

    @Test("search fails with an invalid-query error and its payload")
    func searchFailsWithInvalidQuery() async throws {
        let repository = FailingProductRepository(error: .invalidQuery("!!"))
        try await repository.search(query: "!!").probing { reader in
            // The matcher can inspect associated values, which is useful
            // when the error is not Equatable.
            try await reader.expectError("invalid query error") { error in
                guard case SearchError.invalidQuery(let query) = error else { return false }
                return query == "!!"
            }
        }
    }
}

@MainActor
@Suite("SearchViewModel error paths")
struct SearchViewModelErrorTests {

    @Test("the view model turns a failure into .error state")
    func viewModelTurnsFailureIntoErrorState() async throws {
        let clock = TestClock()
        let viewModel = SearchViewModel(
            repository: FailingProductRepository(error: .networkUnavailable),
            clock: clock
        )

        // The view model's `catch` consumes the error, so `results` never
        // fails. The reader sees an .error value instead.
        // Set the query before collecting, so the debounce timer that the
        // test waits for is the one for this query.
        viewModel.update(query: "anything")

        try await viewModel.results.asFlow().probing { reader in
            try await reader.expectValue(.idle)
            try await clock.waitForSleepers(1)
            await clock.advance(by: .milliseconds(300))
            try await reader.expectValue(.error("Search failed. Please try again."))
        }
    }
}
