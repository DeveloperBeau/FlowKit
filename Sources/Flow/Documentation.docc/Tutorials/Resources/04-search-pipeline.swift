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

    init(repository: ProductRepository) {
        self.repository = repository
    }

    func update(query: String) async {
        await queryFlow.send(query)
    }
}
