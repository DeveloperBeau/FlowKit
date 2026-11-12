import Testing

/// Checks that the import scanner accepts real import forms and ignores the rest.
@Suite("Import scanner")
struct SwiftImportScannerTests {
    private static let fuzzSeed: UInt64 = 20_261_112

    @Test("Comments and strings that mention import are not imports")
    func commentsAndStringsAreNotImports() {
        let samples = [
            "// import FlowUI\n",
            "/* import FlowUI */\n",
            "let note = \"import FlowUI\"\n",
            "let block = \"\"\"\nimport FlowUI\n\"\"\"\n",
            "#\"import FlowUI\"#\n",
            "let value = \"prefix import FlowUI suffix\"\n"
        ]
        for sample in samples {
            let found = SwiftImport.scan(sample)
            #expect(found.isEmpty, "Reported \(found.map(\.moduleName)) for \(sample)")
        }
        let mixed = """
        // import FlowUI
        let note = "import FlowUI"
        import Foundation
        """
        #expect(SwiftImport.scan(mixed).map(\.moduleName) == ["Foundation"])
    }

    @Test("Named import forms keep the module and the line")
    func namedImportForms() {
        let accepted: [(String, [String])] = [
            ("@testable import FlowCore", ["FlowCore"]),
            ("package import FlowCore", ["FlowCore"]),
            ("@_exported import FlowSharedModels", ["FlowSharedModels"]),
            ("internal import AsyncAlgorithms", ["AsyncAlgorithms"]),
            ("public import FlowCore", ["FlowCore"]),
            ("private import FlowCore", ["FlowCore"]),
            ("fileprivate import FlowCore", ["FlowCore"]),
            ("import typealias Foundation.Date", ["Foundation"]),
            ("import struct Foundation.Date", ["Foundation"]),
            ("import class Foundation.NSNull", ["Foundation"]),
            ("import enum Foundation.ComparisonResult", ["Foundation"]),
            ("import protocol Foundation.NSCopying", ["Foundation"]),
            ("import let Foundation.NSNotFound", ["Foundation"]),
            ("import var Foundation.NSNotFound", ["Foundation"]),
            ("import func Foundation.sin", ["Foundation"]),
            ("/* c */ import FlowUI // tail", ["FlowUI"]),
            ("@testable @_exported import FlowCore", ["FlowCore"]),
            ("@_exported @testable import FlowCore", ["FlowCore"]),
            ("import Foo; import Bar", ["Foo", "Bar"]),
            ("@preconcurrency import Foundation", ["Foundation"]),
            ("@_implementationOnly import Foundation", ["Foundation"])
        ]
        for (source, modules) in accepted {
            #expect(SwiftImport.scan(source).map(\.moduleName) == modules, "\(source)")
        }
        let lines = "import Foundation\n@testable import FlowCore\n"
        #expect(SwiftImport.scan(lines).map(\.line) == [1, 2])
        // `open` is not an import access level. Record the module anyway so the edge is not missed.
        #expect(SwiftImport.scan("open import FlowUI").map(\.moduleName) == ["FlowUI"])
    }

    @Test("Seeded fuzz of import lines accepts valid forms and rejects non-imports")
    func seededFuzzAcceptsValidFormsAndRejectsNonImports() {
        print("Swift import scanner fuzz seed: \(Self.fuzzSeed)")
        var generator = SplitMix64(state: Self.fuzzSeed)
        var failures: [String] = []

        let attributes = [
            "",
            "@testable",
            "@_exported",
            "@preconcurrency",
            "@_implementationOnly",
            "@testable @_exported",
            "@_exported @testable"
        ]
        let modifiers = ["", "private", "fileprivate", "internal", "package", "public"]
        let kinds = ["", "typealias", "struct", "class", "enum", "protocol", "let", "var", "func"]
        let gaps = [" ", "  ", "\t"]

        for attribute in attributes {
            for modifier in modifiers {
                for kind in kinds {
                    let module = "M\(generator.next() % 100_000)"
                    let gap = gaps[Int(generator.next() % UInt64(gaps.count))]
                    var pieces: [String] = []
                    if !attribute.isEmpty { pieces.append(attribute) }
                    if !modifier.isEmpty { pieces.append(modifier) }
                    pieces.append("import")
                    if !kind.isEmpty { pieces.append(kind) }
                    var path = module
                    if generator.next() % 2 == 0 {
                        path += ".T\(generator.next() % 1_000)"
                    }
                    pieces.append(path)
                    var line = pieces.joined(separator: gap)
                    if generator.next() % 2 == 0 {
                        line = "/* note */ " + line
                    }
                    if generator.next() % 2 == 0 {
                        line = "// leading\n" + line
                    }
                    if generator.next() % 2 == 0 {
                        line += " // trailing"
                    }
                    let found = SwiftImport.scan(line).map(\.moduleName)
                    if found != [module] {
                        failures.append("accepted \(found) for [\(line)]")
                    }
                }
            }
        }

        for _ in 0..<64 {
            let name = "N\(generator.next() % 100_000)"
            let other = "O\(generator.next() % 100_000)"
            let templates = [
                "// import \(name)",
                "/* import \(name) */",
                "\"import \(name)\"",
                "let \(name) = \"import \(name)\"",
                "func \(name)() {}",
                "import",
                "import 9Nope",
                "\(name) import \(other)",
                "not an import",
                "#\"import \(name)\"#",
                "let block = \"\"\"\nimport \(name)\n\"\"\""
            ]
            let sample = templates[Int(generator.next() % UInt64(templates.count))]
            let found = SwiftImport.scan(sample)
            if !found.isEmpty {
                failures.append("rejected poorly \(found.map(\.moduleName)) for [\(sample)]")
            }
        }

        let message = failures.prefix(8).joined(separator: "\n")
        #expect(failures.isEmpty, "\(failures.count) fuzz failures\n\(message)")
    }
}

/// Deterministic generator so the fuzz run can be repeated from the printed seed.
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
