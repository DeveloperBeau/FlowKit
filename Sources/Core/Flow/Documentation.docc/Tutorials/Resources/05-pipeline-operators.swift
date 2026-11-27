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

    // The pipeline: debounce → deduplicate → search → map → catch errors
    private func buildPipeline() -> Flow<SearchState> {
        queryFlow.asFlow()
            .debounce(for: .milliseconds(300))
            .removeDuplicates()
            .flatMapLatest { [repository] query -> Flow<SearchState> in
                guard !query.isEmpty else { return Flow(of: .idle) }
                // `catch` sits inside flatMapLatest, so one failed search
                // becomes an .error value and the outer pipeline keeps running.
                return repository.search(query: query)
                    .map { SearchState.loaded($0) }
                    .catch { _, collector in
                        await collector.emit(.error("Search failed. Please try again."))
                    }
            }
    }

    init(repository: ProductRepository) {
        self.repository = repository
    }

    func update(query: String) {
        queryFlow.send(query)
    }
}
