import Foundation

struct Product: Identifiable, Sendable, Equatable {
    let id: UUID
    let name: String
    let price: Decimal
}
