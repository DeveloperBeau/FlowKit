import Foundation
import Flow

struct Product: Identifiable, Sendable, Equatable {
    let id: UUID
    let name: String
    let price: Decimal
}

protocol ProductRepository: Sendable {
    func search(query: String) -> ThrowingFlow<[Product]>
}

enum SearchState: Sendable, Equatable {
    case idle
    case loaded([Product])
    case error(String)
}

@Observable
@MainActor
final class SearchViewModel {
    private let repository: ProductRepository
    private let queryFlow = MutableStateFlow("")

    // Expose a hot StateFlow so every subscriber gets the current value
    // immediately. The pipeline stops collecting 5 seconds after the last
    // subscriber leaves, keeping the subscription alive across brief
    // navigations or SwiftUI view rebuilds.
    let results: any StateFlow<SearchState>

    init(repository: ProductRepository) {
        self.repository = repository
        self.results = queryFlow.asFlow()
            .debounce(for: .milliseconds(300))
            .removeDuplicates()
            .flatMapLatest { [repository] query -> ThrowingFlow<SearchState> in
                guard !query.isEmpty else {
                    return ThrowingFlow { collector in try await collector.emit(.idle) }
                }
                return repository.search(query: query).map { .loaded($0) }
            }
            .catch { _, collector in
                await collector.emit(.error("Search failed. Please try again."))
            }
            .asStateFlow(
                initialValue: .idle,
                strategy: .whileSubscribed(stopTimeout: .seconds(5))
            )
    }

    func update(query: String) async {
        await queryFlow.send(query)
    }
}
