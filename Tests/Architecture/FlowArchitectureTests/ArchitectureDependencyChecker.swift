/// Compares the ring map with `Package.swift` and with the imports in each target.
struct ArchitectureDependencyChecker {
    private static let manifestFile = "Package.swift"
    private static let mapFile = "Tests/Architecture/FlowArchitectureTests/ModulePlacement.swift"
    private static let rulesFile = "Tests/Architecture/FlowArchitectureTests/SameRingDependency.swift"

    static func violations(
        targets: [PackageTarget],
        importsByTarget: [String: [SwiftImport]],
        placements: [ModulePlacement] = ModulePlacement.all,
        exceptions: [KnownDependencyException] = KnownDependencyException.all
    ) -> [DependencyViolation] {
        var violations: [DependencyViolation] = []
        var placementByName: [String: ModulePlacement] = [:]
        for placement in placements {
            if placementByName[placement.moduleName] != nil {
                violations.append(
                    make(
                        target: placement.moduleName,
                        importedModule: placement.moduleName,
                        file: mapFile,
                        line: 1,
                        rule: .duplicateTarget,
                        detail: "The ring map lists this module more than once."
                    )
                )
            } else {
                placementByName[placement.moduleName] = placement
            }
        }

        var targetByName: [String: PackageTarget] = [:]
        for target in targets {
            if targetByName[target.name] != nil {
                violations.append(
                    make(
                        target: target.name,
                        importedModule: target.name,
                        file: manifestFile,
                        line: target.nameLine,
                        rule: .duplicateTarget,
                        detail: "Package.swift declares this target more than once."
                    )
                )
            } else {
                targetByName[target.name] = target
            }
        }

        for ring in Ring.allCases where SameRingDependency.rule(for: ring) == nil {
            violations.append(
                make(
                    target: ring.title,
                    importedModule: ring.title,
                    file: rulesFile,
                    line: 1,
                    rule: .missingSameRingRule,
                    detail: "This ring has no same-ring rule."
                )
            )
        }

        for target in targets {
            guard let placement = placementByName[target.name] else {
                violations.append(
                    make(
                        target: target.name,
                        importedModule: target.name,
                        file: manifestFile,
                        line: target.nameLine,
                        rule: .missingRingPlacement,
                        detail: "Package.swift declares this target and the ring map has no entry for it."
                    )
                )
                continue
            }
            violations.append(contentsOf: placementViolations(target: target, placement: placement, placements: placementByName))
        }

        for placement in placements where targetByName[placement.moduleName] == nil {
            violations.append(
                make(
                    target: placement.moduleName,
                    importedModule: placement.moduleName,
                    file: mapFile,
                    line: 1,
                    rule: .staleRingPlacement,
                    detail: "The ring map lists this module and Package.swift has no target with that name."
                )
            )
        }

        let packageNames = Set(targetByName.keys)
        var raw: [DependencyViolation] = []

        for target in targets {
            guard let importer = placementByName[target.name] else { continue }
            for dependency in target.dependencies {
                guard packageNames.contains(dependency.name) else {
                    raw.append(
                        make(
                            target: target.name,
                            importedModule: dependency.name,
                            file: manifestFile,
                            line: dependency.line,
                            rule: .unmappedDependency,
                            detail: "Package.swift lists this dependency and it is not a target of the package."
                        )
                    )
                    continue
                }
                guard let imported = placementByName[dependency.name] else {
                    raw.append(
                        make(
                            target: target.name,
                            importedModule: dependency.name,
                            file: manifestFile,
                            line: dependency.line,
                            rule: .missingRingPlacement,
                            detail: "This dependency has no entry in the ring map."
                        )
                    )
                    continue
                }
                if let rule = brokenRule(from: importer, isTest: target.isTest, to: imported) {
                    raw.append(
                        dependencyViolation(
                            target: target.name,
                            dependency: dependency.name,
                            file: manifestFile,
                            line: dependency.line,
                            rule: rule,
                            importer: importer,
                            imported: imported
                        )
                    )
                }
            }

            let declared = Set(target.dependencies.map(\.name))
            for item in importsByTarget[target.name] ?? [] {
                guard packageNames.contains(item.moduleName) else { continue }
                guard let imported = placementByName[item.moduleName] else {
                    raw.append(
                        make(
                            target: target.name,
                            importedModule: item.moduleName,
                            file: item.file,
                            line: item.line,
                            rule: .missingRingPlacement,
                            detail: "This import has no entry in the ring map."
                        )
                    )
                    continue
                }
                if let rule = brokenRule(from: importer, isTest: target.isTest, to: imported) {
                    raw.append(
                        dependencyViolation(
                            target: target.name,
                            dependency: item.moduleName,
                            file: item.file,
                            line: item.line,
                            rule: rule,
                            importer: importer,
                            imported: imported
                        )
                    )
                }
                if !declared.contains(item.moduleName) {
                    raw.append(
                        make(
                            target: target.name,
                            importedModule: item.moduleName,
                            file: item.file,
                            line: item.line,
                            rule: .undeclaredImport,
                            detail: "Package.swift does not list \(item.moduleName) as a dependency of \(target.name)."
                        )
                    )
                }
            }
        }

        violations.append(contentsOf: raw.filter { !isSuppressed($0, by: exceptions) })
        violations.append(contentsOf: exceptionViolations(exceptions, raw: raw))
        return violations.sorted(by: sort)
    }

    /// Nil when the dependency is allowed.
    static func brokenRule(
        from importer: ModulePlacement,
        isTest: Bool,
        to imported: ModulePlacement
    ) -> DependencyViolation.Rule? {
        // The architecture test checks the graph. It must not join it.
        if !importer.mayImportPackageTargets {
            return .architectureTestImport
        }
        if imported.ring < importer.ring {
            return nil
        }
        if imported.ring == importer.ring {
            guard let rule = SameRingDependency.rule(for: importer.ring) else {
                return .sidewaysDependency
            }
            if isTest && rule.testsMayDependOnAnyModuleInRing {
                return nil
            }
            if !isTest && rule.allowsProduction(importer: importer.moduleName, imported: imported.moduleName) {
                return nil
            }
            return .sidewaysDependency
        }
        if isTest && SameRingDependency.testSupportModules.contains(imported.moduleName) {
            return nil
        }
        return .outwardDependency
    }

    private static func placementViolations(
        target: PackageTarget,
        placement: ModulePlacement,
        placements: [String: ModulePlacement]
    ) -> [DependencyViolation] {
        var violations: [DependencyViolation] = []
        if placement.isTest != target.isTest {
            violations.append(
                make(
                    target: target.name,
                    importedModule: placement.subject ?? target.name,
                    file: mapFile,
                    line: 1,
                    rule: .misplacedTest,
                    detail: "Package.swift and the ring map disagree on whether this target is a test."
                )
            )
        }
        if let subject = placement.subject {
            guard let subjectPlacement = placements[subject] else {
                violations.append(
                    make(
                        target: target.name,
                        importedModule: subject,
                        file: mapFile,
                        line: 1,
                        rule: .misplacedTest,
                        detail: "The ring map says this test exercises \(subject) and that module is not in the map."
                    )
                )
                return violations
            }
            if !placement.isTest {
                violations.append(
                    make(
                        target: target.name,
                        importedModule: subject,
                        file: mapFile,
                        line: 1,
                        rule: .misplacedTest,
                        detail: "The ring map gives this library a module it tests."
                    )
                )
            }
            if placement.ring != subjectPlacement.ring {
                violations.append(
                    make(
                        target: target.name,
                        importedModule: subject,
                        file: mapFile,
                        line: 1,
                        rule: .misplacedTest,
                        detail: "\(target.name) is in the \(placement.ring.title) ring and \(subject) is in the \(subjectPlacement.ring.title) ring. A test sits in the ring of the module it tests."
                    )
                )
            }
        } else if placement.isTest && placement.mayImportPackageTargets {
            violations.append(
                make(
                    target: target.name,
                    importedModule: target.name,
                    file: mapFile,
                    line: 1,
                    rule: .misplacedTest,
                    detail: "A test that may import package targets needs the module it tests."
                )
            )
        }
        return violations
    }

    private static func exceptionViolations(
        _ exceptions: [KnownDependencyException],
        raw: [DependencyViolation]
    ) -> [DependencyViolation] {
        var violations: [DependencyViolation] = []
        var seen: Set<String> = []
        for exception in exceptions {
            let key = "\(exception.target)|\(exception.importedModule)|\(exception.file)"
            if !seen.insert(key).inserted {
                violations.append(
                    make(
                        target: exception.target,
                        importedModule: exception.importedModule,
                        file: exception.file,
                        line: exception.line,
                        rule: .duplicateKnownException,
                        detail: "The known exception list names this import more than once."
                    )
                )
            }
            let matched = raw.contains { finding in
                finding.target == exception.target
                    && finding.importedModule == exception.importedModule
                    && finding.file == exception.file
                    && exception.kind.matches(finding.rule)
            }
            if !matched {
                violations.append(
                    make(
                        target: exception.target,
                        importedModule: exception.importedModule,
                        file: exception.file,
                        line: exception.line,
                        rule: .staleKnownException,
                        detail: "The known exception list names this import and the sources no longer contain it."
                    )
                )
            }
        }
        return violations
    }

    private static func isSuppressed(
        _ violation: DependencyViolation,
        by exceptions: [KnownDependencyException]
    ) -> Bool {
        exceptions.contains { exception in
            guard exception.target == violation.target,
                  exception.importedModule == violation.importedModule,
                  exception.file == violation.file else {
                return false
            }
            switch violation.rule {
            case .undeclaredImport:
                return true
            case .outwardDependency, .sidewaysDependency:
                return exception.kind == .ringViolation
            default:
                return false
            }
        }
    }

    private static func dependencyViolation(
        target: String,
        dependency: String,
        file: String,
        line: Int,
        rule: DependencyViolation.Rule,
        importer: ModulePlacement,
        imported: ModulePlacement
    ) -> DependencyViolation {
        let detail: String
        switch rule {
        case .outwardDependency:
            detail = "\(imported.moduleName) is in the \(imported.ring.title) ring and \(importer.moduleName) is in the \(importer.ring.title) ring. A module may depend only on its own ring or an inner ring."
        case .sidewaysDependency:
            detail = "Both modules are in the \(importer.ring.title) ring. The same-ring rule does not allow \(importer.moduleName) to depend on \(imported.moduleName)."
        case .architectureTestImport:
            detail = "The architecture test checks the graph and must not import a package target."
        default:
            detail = "The dependency is not allowed."
        }
        return make(
            target: target,
            importedModule: dependency,
            file: file,
            line: line,
            rule: rule,
            detail: detail
        )
    }

    private static func make(
        target: String,
        importedModule: String,
        file: String,
        line: Int,
        rule: DependencyViolation.Rule,
        detail: String
    ) -> DependencyViolation {
        DependencyViolation(
            target: target,
            importedModule: importedModule,
            file: file,
            line: line,
            rule: rule,
            detail: detail
        )
    }

    private static func sort(_ lhs: DependencyViolation, _ rhs: DependencyViolation) -> Bool {
        if lhs.file != rhs.file { return lhs.file < rhs.file }
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        if lhs.target != rhs.target { return lhs.target < rhs.target }
        if lhs.importedModule != rhs.importedModule { return lhs.importedModule < rhs.importedModule }
        return lhs.rule.rawValue < rhs.rule.rawValue
    }
}
