import Testing
import Flow
import FlowTesting
import FlowTestClock

struct Product: Identifiable, Sendable, Equatable {
    let id: UUID
    let name: String
    let price: Decimal
}

protocol ProductRepository: Sendable {
    func search(query: String) -> ThrowingFlow<[Product]>
}

final class StubProductRepository: ProductRepository, @unchecked Sendable {
    var stubbedProducts: [Product] = []

    func search(query: String) -> ThrowingFlow<[Product]> {
        ThrowingFlow { collector in
            try await collector.emit(self.stubbedProducts)
        }
    }
}

// Use TestClock to advance virtual time. No real sleeps, no flaky CI.
@Test("debounce suppresses keystrokes within 300 ms")
func debounceSupressesRapidKeystrokes() async throws {
    let clock = TestClock()
    let queries = MutableStateFlow("")
    let repository = StubProductRepository()
    repository.stubbedProducts = [
        Product(id: UUID(), name: "Swift Hoodie", price: 49.99)
    ]

    try await queries.asFlow()
        .debounce(for: .milliseconds(300), clock: clock)
        .removeDuplicates()
        .flatMapLatest { query -> ThrowingFlow<[Product]> in
            guard !query.isEmpty else { return ThrowingFlow { _ in } }
            return repository.search(query: query)
        }
        .test { tester in
            // Rapid keystrokes, each within the debounce window
            await queries.send("s")
            await clock.advance(by: .milliseconds(100))
            await queries.send("sw")
            await clock.advance(by: .milliseconds(100))
            await queries.send("swi")

            // No results yet because the debounce window hasn't closed
            await tester.expectNoValue(within: .milliseconds(50))

            // Advance past the 300 ms debounce window
            await clock.advance(by: .milliseconds(400))

            // Now the pipeline fires exactly once with the latest query
            let results = try await tester.awaitValue()
            #expect(results.count == 1)
            #expect(results[0].name == "Swift Hoodie")
        }
}
