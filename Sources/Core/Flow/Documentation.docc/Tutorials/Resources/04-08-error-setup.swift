import Testing
import Flow
import FlowTesting

// MARK: - Error type

enum SearchError: Error, Equatable {
    case networkUnavailable
    case invalidQuery(String)
}

// MARK: - Failing fake repository

struct FailingProductRepository: ProductRepositoryProtocol {
    let error: SearchError

    func search(_ query: String) -> ThrowingFlow<[Product]> {
        ThrowingFlow { downstream in
            throw error
        }
    }
}
