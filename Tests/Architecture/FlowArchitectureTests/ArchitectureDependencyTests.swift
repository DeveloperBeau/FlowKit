import Foundation
import Testing

/// Reads the package on disk and fails when a dependency points the wrong way.
@Suite("Architecture dependencies")
struct ArchitectureDependencyTests {
    @Test("Every target in Package.swift is in the ring map")
    func everyTargetIsPlaced() throws {
        let graph = try loadGraph()
        let violations = check(graph).filter(isPlacementRule)
        expectNone(violations)
        let targetNames = Set(graph.targets.map(\.name))
        let placedNames = Set(ModulePlacement.all.map(\.moduleName))
        #expect(targetNames == placedNames)
        #expect(Set(SameRingDependency.all.map(\.ring)) == Set(Ring.allCases))
        for placement in ModulePlacement.all {
            #expect(!placement.reason.isEmpty)
            #expect(!placement.reason.contains("\n"))
        }
        let core = graph.targets.first { $0.name == "FlowCore" }
        let sharedModels = core?.dependencies.first { $0.name == "FlowSharedModels" }
        #expect(sharedModels != nil)
        #expect(sharedModels?.line == 56)
        #expect(dependencyNames("FlowOperators", in: graph.targets) == ["FlowCore"])
        #expect(
            dependencyNames("FlowSimulationTests", in: graph.targets)
                == ["Flow", "FlowTesting", "FlowTestSupport"]
        )
        #expect(dependencyNames("FlowSharedModels", in: graph.targets) == [])
        #expect(dependencyNames("FlowArchitectureTests", in: graph.targets) == [])
    }

    @Test("Declared dependencies point inward")
    func declaredDependenciesPointInward() throws {
        let violations = try check(loadGraph()).filter { violation in
            violation.file == "Package.swift" && isDirectionRule(violation)
        }
        expectNone(violations)
    }

    @Test("Source imports point inward")
    func sourceImportsPointInward() throws {
        let violations = try check(loadGraph()).filter { violation in
            violation.file != "Package.swift" && isDirectionRule(violation)
        }
        expectNone(violations)
    }

    @Test("Source imports are declared in Package.swift")
    func sourceImportsAreDeclared() throws {
        let violations = try check(loadGraph()).filter { $0.rule == .undeclaredImport }
        expectNone(violations)
    }

    @Test("Every known exception still matches a real import")
    func knownExceptionsStillMatch() throws {
        let violations = try check(loadGraph()).filter { violation in
            violation.rule == .staleKnownException || violation.rule == .duplicateKnownException
        }
        expectNone(violations)
        #expect(!KnownDependencyException.all.isEmpty)
        for exception in KnownDependencyException.all {
            #expect(exception.kind == .undeclaredImport)
            #expect(!exception.reason.isEmpty)
            #expect(!exception.reason.contains("\n"))
        }
    }

    @Test("A comment or string in an inner module is not a dependency")
    func commentOrStringInInnerModuleIsNotADependency() throws {
        var graph = try loadGraph()
        let relative = "Sources/Shared/FlowSharedModels/SharingStrategy.swift"
        let root = PackageTarget.packageRoot(startingFrom: #filePath)
        let url = root.appendingPathComponent(relative)
        var text = try String(contentsOf: url, encoding: .utf8)
        text += "\n// import FlowUI\nprivate let note = \"import FlowUI\"\n"
        let scanned = SwiftImport.scan(text).map { item in
            SwiftImport(moduleName: item.moduleName, line: item.line, file: relative)
        }
        #expect(scanned.allSatisfy { $0.moduleName != "FlowUI" })
        var imports = graph.importsByTarget["FlowSharedModels"] ?? []
        imports.removeAll { $0.file == relative }
        imports.append(contentsOf: scanned)
        graph.importsByTarget["FlowSharedModels"] = imports
        let violations = ArchitectureDependencyChecker.violations(
            targets: graph.targets,
            importsByTarget: graph.importsByTarget
        )
        let aboutFlowUI = violations.filter { $0.importedModule == "FlowUI" }
        expectNone(aboutFlowUI)
    }
}

private func loadGraph() throws -> PackageTarget.Graph {
    try PackageTarget.loadGraph(from: PackageTarget.packageRoot(startingFrom: #filePath))
}

private func check(_ graph: PackageTarget.Graph) -> [DependencyViolation] {
    ArchitectureDependencyChecker.violations(
        targets: graph.targets,
        importsByTarget: graph.importsByTarget
    )
}

private func dependencyNames(_ name: String, in targets: [PackageTarget]) -> [String] {
    targets.first { $0.name == name }?.dependencies.map(\.name) ?? []
}

private func isPlacementRule(_ violation: DependencyViolation) -> Bool {
    switch violation.rule {
    case .missingRingPlacement, .staleRingPlacement, .misplacedTest, .duplicateTarget, .missingSameRingRule:
        true
    default:
        false
    }
}

private func isDirectionRule(_ violation: DependencyViolation) -> Bool {
    switch violation.rule {
    case .outwardDependency, .sidewaysDependency, .architectureTestImport, .unmappedDependency:
        true
    default:
        false
    }
}

private func expectNone(_ violations: [DependencyViolation]) {
    let message = violations.map(\.description).joined(separator: "\n")
    #expect(violations.isEmpty, "\(message)")
}
