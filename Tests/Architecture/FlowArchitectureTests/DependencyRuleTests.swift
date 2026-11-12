import Testing

/// Checks the ring rules on a small graph so a bad edge fails with a named rule.
@Suite("Dependency rules")
struct DependencyRuleTests {
    @Test("An inner library target may not declare an outer dependency")
    func outwardManifestDependencyFails() {
        let violations = check(
            targets: [
                target("FlowSharedModels", dependencies: [("FlowUI", 9)]),
                target("FlowUI")
            ],
            imports: [:]
        )
        #expect(violations.count == 1)
        expectFields(
            violations[0],
            target: "FlowSharedModels",
            module: "FlowUI",
            file: "Package.swift",
            line: 9,
            rule: "outward dependency"
        )
    }

    @Test("A library target may not import a later module in its ring")
    func sidewaysImportFails() {
        let violations = check(
            targets: [
                target("FlowCore"),
                target("FlowOperators")
            ],
            imports: [
                "FlowCore": [
                    SwiftImport(
                        moduleName: "FlowOperators",
                        line: 4,
                        file: "Sources/Core/FlowCore/Flow/Flow.swift"
                    )
                ]
            ]
        )
        let sideways = violations.first { $0.rule == .sidewaysDependency }
        let undeclared = violations.first { $0.rule == .undeclaredImport }
        #expect(sideways != nil)
        #expect(undeclared != nil)
        if let sideways {
            expectFields(
                sideways,
                target: "FlowCore",
                module: "FlowOperators",
                file: "Sources/Core/FlowCore/Flow/Flow.swift",
                line: 4,
                rule: "sideways dependency"
            )
        }
    }

    @Test("An undeclared exception does not hide a sideways import")
    func undeclaredExceptionDoesNotHideSideways() {
        let exception = KnownDependencyException(
            target: "FlowCore",
            importedModule: "FlowOperators",
            file: "Sources/Core/FlowCore/Flow/Flow.swift",
            line: 4,
            kind: .undeclaredImport,
            reason: "Recorded as undeclared only."
        )
        let violations = check(
            targets: [
                target("FlowCore"),
                target("FlowOperators")
            ],
            imports: [
                "FlowCore": [
                    SwiftImport(
                        moduleName: "FlowOperators",
                        line: 4,
                        file: "Sources/Core/FlowCore/Flow/Flow.swift"
                    )
                ]
            ],
            exceptions: [exception]
        )
        #expect(violations.contains { $0.rule == .sidewaysDependency })
        #expect(!violations.contains { $0.rule == .undeclaredImport })
    }

    @Test("A test may import test support in an outer ring")
    func testMayImportTestSupport() {
        let violations = check(
            targets: [
                target("FlowCore"),
                target("FlowCoreTests", test: true, dependencies: [("FlowTesting", 3)]),
                target("FlowTesting")
            ],
            imports: [
                "FlowCoreTests": [
                    SwiftImport(
                        moduleName: "FlowTesting",
                        line: 2,
                        file: "Tests/Core/FlowCoreTests/Flow/FlowTests.swift"
                    )
                ]
            ]
        )
        #expect(violations.isEmpty, "\(violations.map(\.description).joined(separator: "\n"))")
    }

    @Test("A test may import another module in the same ring")
    func testMayImportSameRingSibling() {
        let violations = check(
            targets: [
                target("FlowOperators"),
                target("FlowHotStreams"),
                target(
                    "FlowOperatorsTests",
                    test: true,
                    dependencies: [("FlowHotStreams", 8)]
                )
            ],
            imports: [
                "FlowOperatorsTests": [
                    SwiftImport(
                        moduleName: "FlowHotStreams",
                        line: 4,
                        file: "Tests/Core/FlowOperatorsTests/Combining/MergeTests.swift"
                    )
                ]
            ]
        )
        #expect(violations.isEmpty, "\(violations.map(\.description).joined(separator: "\n"))")
    }

    @Test("The architecture test may not import a package target")
    func architectureTestMayNotImportAPackageTarget() {
        let violations = check(
            targets: [
                target("FlowCore"),
                target("FlowArchitectureTests", test: true)
            ],
            imports: [
                "FlowArchitectureTests": [
                    SwiftImport(
                        moduleName: "FlowCore",
                        line: 2,
                        file: "Tests/Architecture/FlowArchitectureTests/ArchitectureDependencyTests.swift"
                    )
                ]
            ]
        )
        let match = violations.first { $0.rule == .architectureTestImport }
        #expect(match != nil)
        if let match {
            expectFields(
                match,
                target: "FlowArchitectureTests",
                module: "FlowCore",
                file: "Tests/Architecture/FlowArchitectureTests/ArchitectureDependencyTests.swift",
                line: 2,
                rule: "architecture test import"
            )
        }
    }

    @Test("An exception for one file does not hide the same import in another file")
    func exceptionForOneFileDoesNotHideAnother() {
        let violations = check(
            targets: [
                target("FlowOperators"),
                target("FlowSharedModels")
            ],
            imports: [
                "FlowOperators": [
                    SwiftImport(
                        moduleName: "FlowSharedModels",
                        line: 1,
                        file: "FlowOperators/A.swift"
                    ),
                    SwiftImport(
                        moduleName: "FlowSharedModels",
                        line: 3,
                        file: "FlowOperators/B.swift"
                    )
                ]
            ],
            exceptions: [
                KnownDependencyException(
                    target: "FlowOperators",
                    importedModule: "FlowSharedModels",
                    file: "FlowOperators/A.swift",
                    line: 1,
                    kind: .undeclaredImport,
                    reason: "Only A.swift is listed."
                )
            ]
        )
        let undeclared = violations.filter { $0.rule == .undeclaredImport }
        #expect(undeclared.count == 1)
        #expect(undeclared.first?.file == "FlowOperators/B.swift")
        #expect(undeclared.first?.line == 3)
        #expect(undeclared.first?.target == "FlowOperators")
        #expect(undeclared.first?.importedModule == "FlowSharedModels")
    }

    @Test("An exception goes stale when its file drops the import, even if another file keeps it")
    func exceptionGoesStaleWhenItsFileDropsTheImport() {
        let violations = check(
            targets: [
                target("FlowOperators"),
                target("FlowSharedModels")
            ],
            imports: [
                "FlowOperators": [
                    SwiftImport(
                        moduleName: "FlowSharedModels",
                        line: 2,
                        file: "FlowOperators/B.swift"
                    )
                ]
            ],
            exceptions: [
                KnownDependencyException(
                    target: "FlowOperators",
                    importedModule: "FlowSharedModels",
                    file: "FlowOperators/A.swift",
                    line: 1,
                    kind: .undeclaredImport,
                    reason: "A.swift no longer imports it."
                )
            ]
        )
        let stale = violations.filter { $0.rule == .staleKnownException }
        #expect(stale.count == 1)
        #expect(stale.first?.file == "FlowOperators/A.swift")
        #expect(stale.first?.target == "FlowOperators")
        #expect(stale.first?.importedModule == "FlowSharedModels")
    }
}

private func check(
    targets: [PackageTarget],
    imports: [String: [SwiftImport]],
    exceptions: [KnownDependencyException] = []
) -> [DependencyViolation] {
    let names = Set(targets.map(\.name))
    let placements = ModulePlacement.all.filter { names.contains($0.moduleName) }
    return ArchitectureDependencyChecker.violations(
        targets: targets,
        importsByTarget: imports,
        placements: placements,
        exceptions: exceptions
    )
}

private func target(
    _ name: String,
    test: Bool = false,
    dependencies: [(String, Int)] = []
) -> PackageTarget {
    PackageTarget(
        name: name,
        nameLine: 1,
        isTest: test,
        path: test ? "Tests/\(name)" : "Sources/\(name)",
        dependencies: dependencies.map { PackageTarget.Dependency(name: $0.0, line: $0.1) }
    )
}

private func expectFields(
    _ violation: DependencyViolation,
    target: String,
    module: String,
    file: String,
    line: Int,
    rule: String
) {
    let text = violation.description
    #expect(text.contains(target))
    #expect(text.contains(module))
    #expect(text.contains("\(file):\(line)"))
    #expect(text.contains(rule))
}
