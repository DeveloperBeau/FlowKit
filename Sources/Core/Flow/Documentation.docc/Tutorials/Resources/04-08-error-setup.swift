import Foundation
import Testing
import Flow
import FlowTesting
// MyApp is the app target that holds ProductRepository.
@testable import MyApp

// MARK: - Error type

enum SearchError: Error, Equatable {
    case networkUnavailable
    case invalidQuery(String)
}

// MARK: - Failing fake repository

struct FailingProductRepository: ProductRepository {
    let error: SearchError

    func search(query: String) -> ThrowingFlow<[Product]> {
        ThrowingFlow { _ in
            throw error
        }
    }
}
