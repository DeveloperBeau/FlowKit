/// One dependency the architecture test rejected, or one bookkeeping error in the map.
struct DependencyViolation: Equatable, Sendable, CustomStringConvertible {
    /// The rule a failure message names.
    enum Rule: String, Sendable, Equatable {
        case outwardDependency = "outward dependency"
        case sidewaysDependency = "sideways dependency"
        case undeclaredImport = "undeclared import"
        case architectureTestImport = "architecture test import"
        case staleKnownException = "stale known exception"
        case duplicateKnownException = "duplicate known exception"
        case missingRingPlacement = "missing ring placement"
        case staleRingPlacement = "stale ring placement"
        case misplacedTest = "misplaced test"
        case unmappedDependency = "unmapped dependency"
        case duplicateTarget = "duplicate target"
        case missingSameRingRule = "missing same-ring rule"
    }

    var target: String
    var importedModule: String
    var file: String
    var line: Int
    var rule: Rule
    var detail: String

    var description: String {
        "\(target) depends on \(importedModule) at \(file):\(line). Rule broken: \(rule.rawValue). \(detail)"
    }
}
