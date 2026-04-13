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

// A stub repository that returns a fixed list of products for any query.
final class StubProductRepository: ProductRepository, @unchecked Sendable {
    var stubbedProducts: [Product] = []

    func search(query: String) -> ThrowingFlow<[Product]> {
        ThrowingFlow { collector in
            try await collector.emit(self.stubbedProducts)
        }
    }
}
