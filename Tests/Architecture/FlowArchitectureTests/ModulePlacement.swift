/// One package target and the ring it belongs to.
struct ModulePlacement: Equatable, Sendable {
    var moduleName: String
    var ring: Ring
    /// Why this module sits in this ring.
    var reason: String
    var isTest: Bool
    /// When false, the target may not depend on any package target.
    var mayImportPackageTargets: Bool
    /// Library target a test exercises. Nil for a library target.
    var subject: String?

    /// Every target in `Package.swift`, library and test.
    ///
    /// A test sits in the ring of the module it exercises, so an import of an
    /// outer product is outward. The architecture test is the exception. It
    /// reads the whole graph and imports no package target, so it sits in
    /// Composition.
    static let all: [ModulePlacement] = [
        library(
            "FlowSharedModels",
            .entities,
            "Shared values with no package imports: Mutex, BufferOverflow, SharingStrategy, and FlowTestError."
        ),
        library(
            "FlowCore",
            .domain,
            "Cold flows, collectors, channels, and FlowScope."
        ),
        library(
            "FlowOperators",
            .domain,
            "Operators on Flow and ThrowingFlow."
        ),
        library(
            "FlowHotStreams",
            .domain,
            "State flows, shared flows, and sharing a cold upstream."
        ),
        library(
            "Flow",
            .domain,
            "Umbrella that re-exports the domain targets and adds no types of its own."
        ),
        library(
            "FlowTestClock",
            .infrastructure,
            "A clock that tests advance by hand, so time stays outside the domain."
        ),
        library(
            "FlowTestingCore",
            .infrastructure,
            "Readers, probes, and TestScope that drive a flow from outside the domain."
        ),
        library(
            "FlowTesting",
            .infrastructure,
            "Umbrella that re-exports the testing targets and FlowTestError."
        ),
        library(
            "FlowTestSupport",
            .infrastructure,
            "Helpers shared by test targets. Not a product, and no product imports it."
        ),
        library(
            "FlowSwiftUI",
            .sharedUI,
            "SwiftUI observation and view modifiers over state flows."
        ),
        library(
            "FlowUIKitBridge",
            .sharedUI,
            "UIKit and AppKit collection of flows."
        ),
        library(
            "FlowUI",
            .sharedUI,
            "Umbrella that re-exports the UI bridges and Flow."
        ),
        tests(
            "FlowSharedModelsTests",
            "FlowSharedModels",
            .entities,
            "Exercises FlowSharedModels, so it sits in Entities with that module."
        ),
        tests(
            "FlowCoreTests",
            "FlowCore",
            .domain,
            "Exercises FlowCore, so it sits in Domain with that module."
        ),
        tests(
            "FlowOperatorsTests",
            "FlowOperators",
            .domain,
            "Exercises FlowOperators, so it sits in Domain with that module."
        ),
        tests(
            "FlowHotStreamsTests",
            "FlowHotStreams",
            .domain,
            "Exercises FlowHotStreams, so it sits in Domain with that module."
        ),
        tests(
            "FlowSimulationTests",
            "Flow",
            .domain,
            "Exercises the Flow product end to end, so it sits in Domain with Flow."
        ),
        tests(
            "FlowPublicAPITests",
            "Flow",
            .domain,
            "Checks that the Flow umbrella re-exports the domain types, so it sits in Domain."
        ),
        tests(
            "FlowTestClockTests",
            "FlowTestClock",
            .infrastructure,
            "Exercises FlowTestClock, so it sits in Infrastructure with that module."
        ),
        tests(
            "FlowTestingCoreTests",
            "FlowTestingCore",
            .infrastructure,
            "Exercises FlowTestingCore, so it sits in Infrastructure with that module."
        ),
        tests(
            "FlowTestingPublicAPITests",
            "FlowTesting",
            .infrastructure,
            "Checks that the FlowTesting umbrella re-exports the testing types, so it sits in Infrastructure."
        ),
        tests(
            "FlowUITests",
            "FlowUI",
            .sharedUI,
            "Exercises the UI bridges, so it sits in Shared UI with FlowUI."
        ),
        ModulePlacement(
            moduleName: "FlowArchitectureTests",
            ring: .composition,
            reason: "Checks the dependency rings. It ships in no product and imports no package target.",
            isTest: true,
            mayImportPackageTargets: false,
            subject: nil
        )
    ]

    private static func library(
        _ name: String,
        _ ring: Ring,
        _ reason: String
    ) -> ModulePlacement {
        ModulePlacement(
            moduleName: name,
            ring: ring,
            reason: reason,
            isTest: false,
            mayImportPackageTargets: true,
            subject: nil
        )
    }

    private static func tests(
        _ name: String,
        _ subject: String,
        _ ring: Ring,
        _ reason: String
    ) -> ModulePlacement {
        ModulePlacement(
            moduleName: name,
            ring: ring,
            reason: reason,
            isTest: true,
            mayImportPackageTargets: true,
            subject: subject
        )
    }
}
