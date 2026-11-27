import Foundation
import Testing
import Flow
import FlowTesting

struct Product: Identifiable, Sendable, Equatable {
    let id: UUID
    let name: String
    let price: Decimal
}

enum SearchState: Sendable, Equatable {
    case idle
    case loaded([Product])
    case error(String)
}

protocol ProductRepository: Sendable {
    func search(query: String) -> ThrowingFlow<[Product]>
}

struct NetworkError: Error {}

final class FailingProductRepository: ProductRepository, @unchecked Sendable {
    func search(query: String) -> ThrowingFlow<[Product]> {
        ThrowingFlow { _ in throw NetworkError() }
    }
}

@Test("catch converts network errors into .error state")
func catchConvertsNetworkErrors() async throws {
    let clock = TestClock()
    // The query is set before collection starts, so the debounce timer the
    // test waits for is the one for this query.
    let queries = MutableStateFlow("swift")
    let repository = FailingProductRepository()

    try await queries.asFlow()
        .debounce(for: .milliseconds(300), clock: clock)
        .removeDuplicates()
        .flatMapLatest { query -> Flow<SearchState> in
            guard !query.isEmpty else { return Flow(of: .idle) }
            return repository.search(query: query)
                .map { SearchState.loaded($0) }
                .catch { _, collector in
                    await collector.emit(.error("Search failed. Please try again."))
                }
        }
        .probing { reader in
            try await clock.waitForSleepers(1)
            await clock.advance(by: .milliseconds(400))

            // The catch handler converts the thrown NetworkError into .error state
            try await reader.expectValue(.error("Search failed. Please try again."))
        }
}
