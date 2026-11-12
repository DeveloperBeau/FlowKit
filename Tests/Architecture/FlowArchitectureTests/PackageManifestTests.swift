import Testing

/// Checks that a dependency list is read in full, or the parse fails by name.
@Suite("Package manifest")
struct PackageManifestTests {
    private static let fuzzSeed: UInt64 = 20_261_113

    @Test("A malformed dependency list throws naming the target and line")
    func malformedDependencyListThrows() {
        let missingName = """
        .target(
            name: "FlowCore",
            dependencies: [
                "FlowSharedModels",
                .product(package: "swift-async-algorithms")
            ],
            path: "Sources/FlowCore"
        )
        """
        let missingNameError = #expect(throws: PackageTarget.LoadFailure.self) {
            try PackageTarget.parseManifest(missingName)
        }
        #expect(missingNameError?.message.contains("FlowCore") == true)
        #expect(missingNameError?.message.contains("line 5") == true)

        let unclosed = """
        .target(
            name: "FlowCore",
            dependencies: [
                "FlowSharedModels"
            ,
            path: "Sources/FlowCore"
        )
        """
        let unclosedError = #expect(throws: PackageTarget.LoadFailure.self) {
            try PackageTarget.parseManifest(unclosed)
        }
        #expect(unclosedError?.message.contains("FlowCore") == true)
        #expect(unclosedError?.message.contains("line 3") == true)

        let namelessTarget = """
        .target(
            name: "FlowCore",
            dependencies: [
                .target(condition: .when(platforms: [.linux]))
            ],
            path: "Sources/FlowCore"
        )
        """
        let namelessTargetError = #expect(throws: PackageTarget.LoadFailure.self) {
            try PackageTarget.parseManifest(namelessTarget)
        }
        #expect(namelessTargetError?.message.contains("FlowCore") == true)
        #expect(namelessTargetError?.message.contains("line 4") == true)
    }

    @Test("Seeded fuzz of dependency lists accepts valid forms and rejects corrupt ones")
    func seededFuzzOfDependencyLists() {
        print("Package manifest fuzz seed: \(Self.fuzzSeed)")
        var generator = SplitMix64(state: Self.fuzzSeed)
        var failures: [String] = []
        let gaps = [" ", "  ", "\n", "\t"]
        let platforms = ["linux", "macOS", "iOS"]

        for index in 0..<32 {
            let count = Int(generator.next() % 5) + 1
            var names: [String] = []
            var entries: [String] = []
            var sawProduct = false
            var sawTarget = false
            for entryIndex in 0..<count {
                let module = "Mod\(index)_\(entryIndex)"
                let gap = gaps[Int(generator.next() % UInt64(gaps.count))]
                let form = Int(generator.next() % 3)
                switch form {
                case 0:
                    names.append(module)
                    entries.append("\"\(module)\"")
                case 1:
                    names.append(module)
                    sawTarget = true
                    if generator.next() % 2 == 0 {
                        let platform = platforms[Int(generator.next() % UInt64(platforms.count))]
                        entries.append(
                            ".target(name: \"\(module)\",\(gap)condition: .when(platforms: [.\(platform)]))"
                        )
                    } else {
                        entries.append(".target(name: \"\(module)\")")
                    }
                default:
                    sawProduct = true
                    let package = "pkg\(entryIndex)"
                    if generator.next() % 2 == 0 {
                        let platform = platforms[Int(generator.next() % UInt64(platforms.count))]
                        entries.append(
                            ".product(name: \"\(module)\",\(gap)package: \"\(package)\", condition: .when(platforms: [.\(platform), .macOS]))"
                        )
                    } else {
                        entries.append(".product(name: \"\(module)\", package: \"\(package)\")")
                    }
                }
            }
            let comment = generator.next() % 2 == 0 ? "\n// note\n" : "\n/* block\n   comment */\n"
            let body = entries.joined(separator: ",\(comment)")
            let trailing = generator.next() % 2 == 0 ? "," : ""
            let valid = manifest(dependencies: body + trailing)
            do {
                let parsed = try PackageTarget.parseManifest(valid)
                let found = parsed.first { $0.name == "FlowCore" }?.dependencies.map(\.name) ?? []
                if found != names {
                    failures.append("valid list \(index) parsed \(found) expected \(names)")
                }
            } catch {
                failures.append("valid list \(index) threw \(error)")
            }

            let unclosed = manifestUnclosed(dependencies: body)
            if parses(unclosed) != nil {
                failures.append("unclosed list \(index) parsed instead of throwing")
            }
            if sawProduct, let parsed = parses(manifest(dependencies: namelessProduct(in: body))) {
                failures.append("product with no name parsed \(parsed)")
            }
            if sawTarget, let parsed = parses(manifest(dependencies: namelessTargetCall(in: body))) {
                failures.append("target with no name parsed \(parsed)")
            }
        }

        let message = failures.prefix(8).joined(separator: "\n")
        #expect(failures.isEmpty, "\(failures.count) manifest fuzz failures\n\(message)")
    }
}

/// A one-target manifest whose dependency list is the given text.
private func manifest(dependencies: String) -> String {
    """
    .target(
        name: "FlowCore",
        dependencies: [
            \(dependencies)
        ],
        path: "Sources/FlowCore"
    )
    """
}

/// The same manifest with the dependency list left open.
private func manifestUnclosed(dependencies: String) -> String {
    """
    .target(
        name: "FlowCore",
        dependencies: [
            \(dependencies)
        ,
        path: "Sources/FlowCore"
    )
    """
}

/// Replaces the first `.product(name:)` call with one that has no name.
private func namelessProduct(in body: String) -> String {
    replacingFirstCall(
        in: body,
        prefix: ".product(name:",
        with: ".product(package: \"swift-async-algorithms\")"
    )
}

/// Replaces the first `.target(name:)` call with one that has no name.
private func namelessTargetCall(in body: String) -> String {
    replacingFirstCall(
        in: body,
        prefix: ".target(name:",
        with: ".target(condition: .when(platforms: [.linux]))"
    )
}

/// Swaps one call, including a nested condition, for a call that omits `name:`.
private func replacingFirstCall(in body: String, prefix: String, with replacement: String) -> String {
    guard let start = body.firstRange(of: prefix) else { return body }
    var depth = 0
    var index = start.lowerBound
    while index < body.endIndex {
        let character = body[index]
        if character == "(" {
            depth += 1
        } else if character == ")" {
            depth -= 1
            if depth == 0 {
                let end = body.index(after: index)
                var updated = body
                updated.replaceSubrange(start.lowerBound..<end, with: replacement)
                return updated
            }
        }
        index = body.index(after: index)
    }
    return body
}

/// Parsed target-dependency names, or nil when the manifest throws.
private func parses(_ source: String) -> [String]? {
    guard let targets = try? PackageTarget.parseManifest(source) else { return nil }
    return targets.first { $0.name == "FlowCore" }?.dependencies.map(\.name)
}

/// Deterministic generator so the manifest fuzz can be repeated from the printed seed.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
