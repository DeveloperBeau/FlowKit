import SwiftUI
import FlowUI

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
    let results: any StateFlow<SearchState>

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

struct SearchView: View {
    let viewModel: SearchViewModel

    // @CollectedState observes the hot StateFlow and re-renders the view
    // whenever SearchState changes. The initial value matches the flow's
    // initialValue so there's no flash on first render.
    @CollectedState var state: SearchState
    @State private var query = ""

    // A property wrapper cannot read another property while it is
    // initialised, so the wrapper is created here with the view model's flow.
    init(viewModel: SearchViewModel) {
        self.viewModel = viewModel
        _state = CollectedState(wrappedValue: .idle, viewModel.results)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .idle:
                    ContentUnavailableView(
                        "Search Products",
                        systemImage: "magnifyingglass",
                        description: Text("Type to find products in the catalog.")
                    )
                case .loaded(let products):
                    List(products) { product in
                        VStack(alignment: .leading) {
                            Text(product.name).font(.headline)
                            Text(product.price, format: .currency(code: "USD"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                case .error(let message):
                    ContentUnavailableView(
                        "Something went wrong",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                }
            }
            .navigationTitle("Products")
            .searchable(text: $query)
            .onChange(of: query) { _, newValue in
                viewModel.update(query: newValue)
            }
        }
    }
}
