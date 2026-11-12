/// Rings from the inside of the package to the outside.
///
/// A dependency may point at the same ring or at a ring closer to the inside.
enum Ring: Int, CaseIterable, Sendable, Comparable {
    case entities = 0
    case domain
    case infrastructure
    case sharedUI
    case features
    case composition

    static func < (lhs: Ring, rhs: Ring) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Name used in failure messages.
    var title: String {
        switch self {
        case .entities:
            "Entities"
        case .domain:
            "Domain"
        case .infrastructure:
            "Infrastructure"
        case .sharedUI:
            "Shared UI"
        case .features:
            "Features"
        case .composition:
            "Composition"
        }
    }
}
