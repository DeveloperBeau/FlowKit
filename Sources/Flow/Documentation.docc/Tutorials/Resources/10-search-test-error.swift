import Testing
import Flow
import FlowTesting
import FlowTestClock

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
    let queries = MutableStateFlow("")
    let repository = FailingProductRepository()

    try await queries.asFlow()
        .debounce(for: .milliseconds(300), clock: clock)
        .removeDuplicates()
        .flatMapLatest { query -> ThrowingFlow<SearchState> in
            guard !query.isEmpty else {
                return ThrowingFlow { collector in try await collector.emit(.idle) }
            }
            return repository.search(query: query).map { SearchState.loaded($0) }
        }
        .catch { _, collector in
            await collector.emit(.error("Search failed. Please try again."))
        }
        .test { tester in
            await queries.send("swift")
            await clock.advance(by: .milliseconds(400))

            // The catch handler converts the thrown NetworkError into .error state
            try await tester.expectValue(.error("Search failed. Please try again."))
        }
}
