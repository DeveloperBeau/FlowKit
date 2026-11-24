import Foundation
import Testing

/// Fails when a product meant for host apps and fixtures can reach a test framework.
///
/// A module that links `Testing` or `XCTest` cannot be linked outside a test
/// bundle. The check walks every package target the product reaches, through
/// the manifest and through source imports, and reads the imports of each.
@Suite("Products that stay free of test frameworks")
struct TestingFreeProductTests {
    private static let testFrameworks: Set<String> = ["Testing", "XCTest"]

    @Test("FlowRecording reaches no target that imports Testing or XCTest")
    func flowRecordingIsFreeOfTestFrameworks() throws {
        let graph = try loadGraph()
        let reached = reachableTargets(from: "FlowRecording", in: graph)
        #expect(
            reached == ["FlowRecording", "Flow", "FlowSharedModels", "FlowCore", "FlowOperators", "FlowHotStreams"]
        )
        let offending = testFrameworkImports(in: reached, graph: graph)
        #expect(offending.isEmpty, "\(offending.joined(separator: "\n"))")
    }

    @Test("The same walk finds the Testing import that FlowTesting reaches")
    func flowTestingReachesATestFramework() throws {
        let graph = try loadGraph()
        let reached = reachableTargets(from: "FlowTesting", in: graph)
        #expect(reached.contains("FlowTestingCore"))
        let offending = testFrameworkImports(in: reached, graph: graph)
        #expect(offending.contains { $0.hasPrefix("Sources/Testing/FlowTestingCore/Testers/FlowReader.swift:") })
    }

    @Test("A test framework import in a target reached only through a source import is found")
    func undeclaredRouteToATestFrameworkIsFound() throws {
        var graph = try loadGraph()
        graph.importsByTarget["FlowCore", default: []].append(
            SwiftImport(moduleName: "FlowTestingCore", line: 1, file: "Sources/Core/FlowCore/Injected.swift")
        )
        let reached = reachableTargets(from: "FlowRecording", in: graph)
        #expect(reached.contains("FlowTestingCore"))
        #expect(!testFrameworkImports(in: reached, graph: graph).isEmpty)
    }

    private func loadGraph() throws -> PackageTarget.Graph {
        try PackageTarget.loadGraph(from: PackageTarget.packageRoot(startingFrom: #filePath))
    }

    /// The target and every package target it reaches, declared or imported.
    private func reachableTargets(from start: String, in graph: PackageTarget.Graph) -> Set<String> {
        let names = Set(graph.targets.map(\.name))
        var reached: Set<String> = []
        var pending = [start]
        while let name = pending.popLast() {
            guard names.contains(name), reached.insert(name).inserted else { continue }
            let declared = graph.targets.first { $0.name == name }?.dependencies.map(\.name) ?? []
            let imported = graph.importsByTarget[name]?.map(\.moduleName) ?? []
            pending.append(contentsOf: declared + imported)
        }
        return reached
    }

    private func testFrameworkImports(in targets: Set<String>, graph: PackageTarget.Graph) -> [String] {
        targets.sorted().flatMap { name in
            (graph.importsByTarget[name] ?? [])
                .filter { Self.testFrameworks.contains($0.moduleName) }
                .map { "\($0.file):\($0.line) imports \($0.moduleName)" }
        }
    }
}
