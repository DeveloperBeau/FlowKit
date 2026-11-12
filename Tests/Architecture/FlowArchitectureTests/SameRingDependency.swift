/// Which modules in one ring may depend on each other.
///
/// A dependency inside a ring is sideways unless this rule names it.
/// Test targets may depend on any module in their own ring. A test is not
/// linked into the library and may build fixtures from a sibling.
/// FlowOperatorsTests imports FlowHotStreams under that rule. The FlowOperators
/// target itself does not.
struct SameRingDependency: Sendable {
    /// One allowed production edge. The importer may depend on the imported module.
    struct ModuleEdge: Hashable, Sendable {
        var importer: String
        var imported: String
    }

    var ring: Ring
    /// Why these edges, and not the other direction, are the ones allowed.
    var reason: String
    var allowedProductionEdges: Set<ModuleEdge>
    var testsMayDependOnAnyModuleInRing: Bool

    /// Testing stack a test may import even when those modules sit further out.
    ///
    /// A library target does not get this pass, so the domain cannot import
    /// the clock or the testers.
    static let testSupportModules: Set<String> = [
        "FlowTestClock",
        "FlowTestingCore",
        "FlowTesting",
        "FlowTestSupport"
    ]

    static let all: [SameRingDependency] = [
        SameRingDependency(
            ring: .entities,
            reason: "Entity modules are shared values. They do not import each other. A second entity module should move the shared type into one module instead of pointing sideways.",
            allowedProductionEdges: [],
            testsMayDependOnAnyModuleInRing: true
        ),
        SameRingDependency(
            ring: .domain,
            reason: "Operators are methods on the cold flow types. Hot streams collect those flows and use the operators. The Flow umbrella only re-exports those three. The cold flow types must not import an operator, a hot stream, or the umbrella.",
            allowedProductionEdges: [
                ModuleEdge(importer: "FlowOperators", imported: "FlowCore"),
                ModuleEdge(importer: "FlowHotStreams", imported: "FlowCore"),
                ModuleEdge(importer: "FlowHotStreams", imported: "FlowOperators"),
                ModuleEdge(importer: "Flow", imported: "FlowCore"),
                ModuleEdge(importer: "Flow", imported: "FlowOperators"),
                ModuleEdge(importer: "Flow", imported: "FlowHotStreams")
            ],
            testsMayDependOnAnyModuleInRing: true
        ),
        SameRingDependency(
            ring: .infrastructure,
            reason: "The clock stands alone. Testing core drives flows and may use the clock. The umbrella re-exports those two. Test support calls into that stack, and no product target imports test support.",
            allowedProductionEdges: [
                ModuleEdge(importer: "FlowTestingCore", imported: "FlowTestClock"),
                ModuleEdge(importer: "FlowTesting", imported: "FlowTestClock"),
                ModuleEdge(importer: "FlowTesting", imported: "FlowTestingCore"),
                ModuleEdge(importer: "FlowTestSupport", imported: "FlowTestClock"),
                ModuleEdge(importer: "FlowTestSupport", imported: "FlowTestingCore"),
                ModuleEdge(importer: "FlowTestSupport", imported: "FlowTesting")
            ],
            testsMayDependOnAnyModuleInRing: true
        ),
        SameRingDependency(
            ring: .sharedUI,
            reason: "The SwiftUI bridge and the UIKit and AppKit bridge are different platforms. They must not import each other. The FlowUI umbrella re-exports both.",
            allowedProductionEdges: [
                ModuleEdge(importer: "FlowUI", imported: "FlowSwiftUI"),
                ModuleEdge(importer: "FlowUI", imported: "FlowUIKitBridge")
            ],
            testsMayDependOnAnyModuleInRing: true
        ),
        SameRingDependency(
            ring: .features,
            reason: "Feature modules are peers. A type they both need belongs in an inner ring. This package has no feature target today.",
            allowedProductionEdges: [],
            testsMayDependOnAnyModuleInRing: true
        ),
        SameRingDependency(
            ring: .composition,
            reason: "A composition root wires the other rings and is not a dependency of another root. The architecture test is the only module in this ring, and it imports no package target.",
            allowedProductionEdges: [],
            testsMayDependOnAnyModuleInRing: true
        )
    ]

    static func rule(for ring: Ring) -> SameRingDependency? {
        all.first { $0.ring == ring }
    }

    func allowsProduction(importer: String, imported: String) -> Bool {
        allowedProductionEdges.contains(ModuleEdge(importer: importer, imported: imported))
    }
}
