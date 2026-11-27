import Testing
import Flow
import FlowTesting
// MyApp is the app target that holds ProductRepository.
@testable import MyApp

@Suite("Repository error paths")
struct RepositoryErrorTests {

    @Test("search fails with a network error")
    func searchFailsWithNetworkError() async throws {
        let repository = FailingProductRepository(error: .networkUnavailable)

        // `search(query:)` returns a ThrowingFlow, which probing reads like a
        // Flow. expectError(_:matching:) reads the failure.
        try await repository.search(query: "anything").probing { reader in
            // The description names the expected error in a failure message.
            // SearchError is Equatable, so the match is a plain comparison.
            try await reader.expectError("network unavailable") { error in
                (error as? SearchError) == .networkUnavailable
            }
        }
    }
}
