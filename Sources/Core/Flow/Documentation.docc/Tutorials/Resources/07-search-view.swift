import SwiftUI
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

struct SearchView: View {
    @Bindable var viewModel: SearchViewModel

    // @CollectedState observes the hot StateFlow and re-renders the view
    // whenever SearchState changes. The initial value matches the flow's
    // initialValue so there's no flash on first render.
    @CollectedState(viewModel.results) var state: SearchState = .idle
    @State private var query = ""

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
                Task { await viewModel.update(query: newValue) }
            }
        }
    }
}
