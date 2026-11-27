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

    // The clock drives the debounce and the stop timeout. Production code
    // uses the default; tests pass a TestClock to control time.
    init(
        repository: ProductRepository,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.repository = repository
        self.results = queryFlow.asFlow()
            .debounce(for: .milliseconds(300), clock: clock)
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
            .asStateFlow(
                initialValue: .idle,
                strategy: .whileSubscribed(stopTimeout: .seconds(5)),
                clock: clock
            )
    }

    func update(query: String) {
        queryFlow.send(query)
    }
}
