# ``Flow``

Kotlin Flow semantics in Swift, built on Swift 6.3 strict concurrency.

## Overview

FlowKit brings the Kotlin Flow mental model to Swift: cold asynchronous streams (``FlowCore/Flow``, ``FlowCore/ThrowingFlow``), hot multicast primitives (``FlowHotStreams/StateFlow``, ``FlowHotStreams/SharedFlow``), a rich operator library, and built-in testing infrastructure with virtual time.

## End-to-end example

A search feature with debouncing, cancellation of in-flight queries, error fallback, and SwiftUI binding:

```swift
import Flow
import FlowUI

@Observable
@MainActor
final class SearchViewModel {
    private let repository: ProductRepository
    private let query = MutableStateFlow("")
    let results: any StateFlow<SearchState>

    init(repository: ProductRepository) {
        self.repository = repository
        self.results = query.asFlow()
            .debounce(for: .milliseconds(300))
            .removeDuplicates()
            .flatMapLatest { query -> ThrowingFlow<[Product]> in
                query.isEmpty ? .empty : repository.search(query)
            }
            .map { SearchState.loaded($0) }
            .catch { _, collector in
                await collector.emit(.error("Search failed"))
            }
            .asStateFlow(initialValue: .idle, strategy: .whileSubscribed(stopTimeout: .seconds(5)))
    }

    func update(query text: String) async {
        await query.send(text)
    }
}

struct SearchView: View {
    @Bindable var viewModel: SearchViewModel
    @CollectedState(viewModel.results) var state: SearchState = .idle
    @State private var query = ""

    var body: some View {
        VStack {
            TextField("Search", text: $query)
                .onChange(of: query) { _, new in
                    Task { await viewModel.update(query: new) }
                }
            switch state {
            case .idle: ContentUnavailableView("Start typing", systemImage: "magnifyingglass")
            case .loaded(let products): List(products) { ProductRow(product: $0) }
            case .error(let message): Text(message).foregroundStyle(.red)
            }
        }
    }
}
```

Every piece, from cold ``FlowCore/Flow`` composition, debouncing, and error handling to hot ``FlowHotStreams/StateFlow`` sharing and SwiftUI binding, is 0.1.0-through-0.4.0 API.

## Topics

### Getting Started

- <doc:HotVsColdStreams>
- <doc:FlowVsThrowingFlow>
- <doc:LifecycleAwareCollection>

### Tutorials

- <doc:tutorials/FlowKit>

### Core Concepts

- <doc:CancellationSemantics>
- <doc:KotlinFlowMigration>
