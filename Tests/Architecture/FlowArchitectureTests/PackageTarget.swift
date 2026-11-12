import Foundation

/// A library or test target read from `Package.swift`.
struct PackageTarget: Equatable, Sendable {
    /// A target dependency written in the manifest, not a product dependency.
    struct Dependency: Equatable, Sendable {
        var name: String
        var line: Int
    }

    /// Targets and the imports in their source files.
    struct Graph: Sendable {
        var targets: [PackageTarget]
        var importsByTarget: [String: [SwiftImport]]
    }

    /// A manifest or source file could not be read.
    struct LoadFailure: Error, CustomStringConvertible, Sendable {
        var message: String
        var description: String { message }
    }

    var name: String
    var nameLine: Int
    var isTest: Bool
    var path: String
    var dependencies: [Dependency]

    /// Package root that contains `Package.swift`, found by walking up from a source file.
    static func packageRoot(startingFrom filePath: String = #filePath) -> URL {
        var url = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let manager = FileManager.default
        while true {
            let manifest = url.appendingPathComponent("Package.swift")
            if manager.fileExists(atPath: manifest.path) {
                return url
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path {
                preconditionFailure("Package.swift was not found by walking up from the test file.")
            }
            url = parent
        }
    }

    /// Reads the manifest and the Swift sources of every target.
    ///
    /// DocC catalogs are skipped. They are documentation, and SwiftPM does not
    /// compile them into the target. Sample snippets import modules the target
    /// does not depend on.
    static func loadGraph(from root: URL) throws -> Graph {
        let manifestURL = root.appendingPathComponent("Package.swift")
        let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
        let targets = try parseManifest(manifest)
        var importsByTarget: [String: [SwiftImport]] = [:]
        for target in targets {
            importsByTarget[target.name] = try imports(in: target, root: root)
        }
        return Graph(targets: targets, importsByTarget: importsByTarget)
    }

    static func parseManifest(_ source: String) throws -> [PackageTarget] {
        var scanner = ManifestScanner(source: source)
        let tokens = scanner.scan()
        var targets: [PackageTarget] = []
        var index = 0
        while index < tokens.count {
            guard isDotWord(tokens, index, words: ["target", "testTarget"]),
                  index + 2 < tokens.count,
                  case .symbol("(", _) = tokens[index + 2] else {
                index += 1
                continue
            }
            let word: String
            if case .word(let name, _) = tokens[index + 1] {
                word = name
            } else {
                index += 1
                continue
            }
            guard let close = matching(tokens, from: index + 2, open: "(", close: ")") else {
                throw LoadFailure(message: "Package.swift has an unclosed parenthesis.")
            }
            let inner = Array(tokens[(index + 3)..<close])
            if declaresTarget(inner) {
                targets.append(try parseTarget(inner, isTest: word == "testTarget"))
            }
            index = close + 1
        }
        return targets
    }

    private static func imports(in target: PackageTarget, root: URL) throws -> [SwiftImport] {
        let directory = root.appendingPathComponent(target.path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw LoadFailure(message: "A target path does not exist: \(target.path).")
        }
        let files = try swiftFiles(in: directory)
        var found: [SwiftImport] = []
        for file in files {
            let relative = try relativePath(of: file, to: root)
            let text = try String(contentsOf: file, encoding: .utf8)
            for item in SwiftImport.scan(text) {
                found.append(
                    SwiftImport(moduleName: item.moduleName, line: item.line, file: relative)
                )
            }
        }
        return found
    }

    private static func swiftFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw LoadFailure(message: "Could not read target sources.")
        }
        var files: [URL] = []
        for case let url as URL in enumerator {
            if url.lastPathComponent.hasSuffix(".docc") {
                enumerator.skipDescendants()
                continue
            }
            if url.pathExtension == "swift" {
                files.append(url)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func relativePath(of file: URL, to root: URL) throws -> String {
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        let filePath = file.resolvingSymlinksInPath().standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(prefix) else {
            throw LoadFailure(message: "A source file was outside the package root.")
        }
        return String(filePath.dropFirst(prefix.count))
    }

    private static func declaresTarget(_ tokens: [ManifestToken]) -> Bool {
        let labels = topLevelLabels(tokens)
        let markers: Set<String> = [
            "path", "dependencies", "swiftSettings", "sources", "exclude",
            "plugins", "linkerSettings", "resources", "cSettings", "cxxSettings"
        ]
        return !labels.isDisjoint(with: markers)
    }

    private static func parseTarget(_ tokens: [ManifestToken], isTest: Bool) throws -> PackageTarget {
        var name: String?
        var nameLine = 1
        var path: String?
        var dependencies: [Dependency] = []
        var index = 0
        var depth = 0
        while index < tokens.count {
            let token = tokens[index]
            switch token {
            case .symbol("(", _), .symbol("[", _):
                depth += 1
            case .symbol(")", _), .symbol("]", _):
                depth -= 1
            case .word(let label, _) where depth == 0 && index + 1 < tokens.count:
                if case .symbol(":", _) = tokens[index + 1] {
                    if label == "name", index + 2 < tokens.count, case .string(let value, let line) = tokens[index + 2] {
                        name = value
                        nameLine = line
                    } else if label == "path", index + 2 < tokens.count, case .string(let value, _) = tokens[index + 2] {
                        path = value
                    } else if label == "dependencies",
                              index + 2 < tokens.count,
                              case .symbol("[", let listLine) = tokens[index + 2] {
                        guard let close = matching(tokens, from: index + 2, open: "[", close: "]") else {
                            let targetName = name ?? declaredName(tokens) ?? "unknown"
                            throw LoadFailure(
                                message: "Target \(targetName) has an unclosed dependency list at line \(listLine)."
                            )
                        }
                        let inner = Array(tokens[(index + 3)..<close])
                        let targetName = name ?? declaredName(tokens) ?? "unknown"
                        dependencies = try parseDependencies(inner, target: targetName)
                        index = close
                    }
                }
            default:
                break
            }
            index += 1
        }
        guard let name else {
            throw LoadFailure(message: "Package.swift has a target with no name.")
        }
        let resolvedPath = path ?? (isTest ? "Tests/\(name)" : "Sources/\(name)")
        return PackageTarget(
            name: name,
            nameLine: nameLine,
            isTest: isTest,
            path: resolvedPath,
            dependencies: dependencies
        )
    }

    private static func parseDependencies(
        _ tokens: [ManifestToken],
        target: String
    ) throws -> [Dependency] {
        var dependencies: [Dependency] = []
        var index = 0
        while index < tokens.count {
            if isDotWord(tokens, index, words: ["product"]) {
                let line = tokenLine(tokens[index + 1])
                guard let close = matchingCall(tokens, dotIndex: index) else {
                    throw LoadFailure(
                        message: "Target \(target) has an unclosed product dependency at line \(line)."
                    )
                }
                let inner = Array(tokens[(index + 3)..<close])
                guard labeledName(inner) != nil else {
                    throw LoadFailure(
                        message: "Target \(target) has a product dependency with no name at line \(line)."
                    )
                }
                index = close + 1
                continue
            }
            if isDotWord(tokens, index, words: ["target", "byName"]) {
                let kind = wordText(tokens[index + 1])
                let line = tokenLine(tokens[index + 1])
                guard let close = matchingCall(tokens, dotIndex: index) else {
                    throw LoadFailure(
                        message: "Target \(target) has an unclosed target dependency at line \(line)."
                    )
                }
                let inner = Array(tokens[(index + 3)..<close])
                let found = labeledName(inner) ?? (kind == "byName" ? bareName(inner) : nil)
                guard let found else {
                    throw LoadFailure(
                        message: "Target \(target) has a target dependency with no name at line \(line)."
                    )
                }
                dependencies.append(Dependency(name: found.name, line: found.line))
                index = close + 1
                continue
            }
            if case .string(let value, let line) = tokens[index] {
                dependencies.append(Dependency(name: value, line: line))
            }
            index += 1
        }
        return dependencies
    }

    /// The `name:` string at the top level of a dependency call.
    ///
    /// A package string on `.product` is not a name. Missing this label is an
    /// error, so a bad call cannot disappear from the list.
    private static func labeledName(_ tokens: [ManifestToken]) -> (name: String, line: Int)? {
        var index = 0
        var depth = 0
        while index < tokens.count {
            switch tokens[index] {
            case .symbol("(", _), .symbol("[", _):
                depth += 1
            case .symbol(")", _), .symbol("]", _):
                depth -= 1
            case .word("name", _) where depth == 0 && index + 2 < tokens.count:
                if case .symbol(":", _) = tokens[index + 1],
                   case .string(let value, let line) = tokens[index + 2] {
                    return (value, line)
                }
            default:
                break
            }
            index += 1
        }
        return nil
    }

    /// `.byName("Module")` passes the module as a bare string.
    private static func bareName(_ tokens: [ManifestToken]) -> (name: String, line: Int)? {
        var index = 0
        var depth = 0
        while index < tokens.count {
            switch tokens[index] {
            case .symbol("(", _), .symbol("[", _):
                depth += 1
            case .symbol(")", _), .symbol("]", _):
                depth -= 1
            case .string(let value, let line) where depth == 0:
                return (value, line)
            default:
                break
            }
            index += 1
        }
        return nil
    }

    private static func declaredName(_ tokens: [ManifestToken]) -> String? {
        var index = 0
        var depth = 0
        while index < tokens.count {
            switch tokens[index] {
            case .symbol("(", _), .symbol("[", _):
                depth += 1
            case .symbol(")", _), .symbol("]", _):
                depth -= 1
            case .word("name", _) where depth == 0 && index + 2 < tokens.count:
                if case .symbol(":", _) = tokens[index + 1],
                   case .string(let value, _) = tokens[index + 2] {
                    return value
                }
            default:
                break
            }
            index += 1
        }
        return nil
    }

    private static func topLevelLabels(_ tokens: [ManifestToken]) -> Set<String> {
        var labels: Set<String> = []
        var depth = 0
        var index = 0
        while index < tokens.count {
            switch tokens[index] {
            case .symbol("(", _), .symbol("[", _):
                depth += 1
            case .symbol(")", _), .symbol("]", _):
                depth -= 1
            case .word(let word, _) where depth == 0 && index + 1 < tokens.count:
                if case .symbol(":", _) = tokens[index + 1] {
                    labels.insert(word)
                }
            default:
                break
            }
            index += 1
        }
        return labels
    }

    private static func isDotWord(
        _ tokens: [ManifestToken],
        _ index: Int,
        words: Set<String>
    ) -> Bool {
        guard index + 1 < tokens.count,
              case .symbol(".", _) = tokens[index],
              case .word(let word, _) = tokens[index + 1] else {
            return false
        }
        return words.contains(word)
    }

    private static func wordText(_ token: ManifestToken) -> String {
        if case .word(let word, _) = token {
            return word
        }
        return ""
    }

    private static func tokenLine(_ token: ManifestToken) -> Int {
        switch token {
        case .word(_, let line), .string(_, let line), .symbol(_, let line):
            return line
        }
    }

    private static func matchingCall(_ tokens: [ManifestToken], dotIndex: Int) -> Int? {
        let paren = dotIndex + 2
        guard paren < tokens.count, case .symbol("(", _) = tokens[paren] else { return nil }
        return matching(tokens, from: paren, open: "(", close: ")")
    }

    private static func matching(
        _ tokens: [ManifestToken],
        from openIndex: Int,
        open: Character,
        close: Character
    ) -> Int? {
        var depth = 0
        var index = openIndex
        while index < tokens.count {
            if case .symbol(let symbol, _) = tokens[index] {
                if symbol == open {
                    depth += 1
                } else if symbol == close {
                    depth -= 1
                    if depth == 0 {
                        return index
                    }
                }
            }
            index += 1
        }
        return nil
    }
}

private enum ManifestToken {
    case word(String, line: Int)
    case string(String, line: Int)
    case symbol(Character, line: Int)
}

private struct ManifestScanner {
    var source: String
    var index: String.Index
    var line: Int

    init(source: String) {
        self.source = source
        self.index = source.startIndex
        self.line = 1
    }

    mutating func scan() -> [ManifestToken] {
        var tokens: [ManifestToken] = []
        while index < source.endIndex {
            let character = source[index]
            if character == "\n" {
                line += 1
                advance()
                continue
            }
            if character == " " || character == "\t" || character == "\r" {
                advance()
                continue
            }
            if character == "/" && peek() == "/" {
                while index < source.endIndex && source[index] != "\n" {
                    advance()
                }
                continue
            }
            if character == "/" && peek() == "*" {
                advance()
                advance()
                var depth = 1
                while index < source.endIndex && depth > 0 {
                    if source[index] == "\n" {
                        line += 1
                        advance()
                        continue
                    }
                    if source[index] == "/" && peek() == "*" {
                        advance()
                        advance()
                        depth += 1
                        continue
                    }
                    if source[index] == "*" && peek() == "/" {
                        advance()
                        advance()
                        depth -= 1
                        continue
                    }
                    advance()
                }
                continue
            }
            if character == "\"" {
                if let token = scanString() {
                    tokens.append(token)
                }
                continue
            }
            if isWordStart(character) {
                let startLine = line
                var word = ""
                while index < source.endIndex && isWordContinuation(source[index]) {
                    word.append(source[index])
                    advance()
                }
                tokens.append(.word(word, line: startLine))
                continue
            }
            tokens.append(.symbol(character, line: line))
            advance()
        }
        return tokens
    }

    private mutating func scanString() -> ManifestToken? {
        let startLine = line
        let multiline = startsWith("\"\"\"")
        let opening = multiline ? 3 : 1
        for _ in 0..<opening where index < source.endIndex {
            advance()
        }
        var value = ""
        while index < source.endIndex {
            if !multiline && source[index] == "\n" {
                break
            }
            if source[index] == "\\" {
                advance()
                if index < source.endIndex {
                    value.append(source[index])
                    if source[index] == "\n" {
                        line += 1
                    }
                    advance()
                }
                continue
            }
            if multiline && startsWith("\"\"\"") {
                advance()
                advance()
                advance()
                return .string(value, line: startLine)
            }
            if !multiline && source[index] == "\"" {
                advance()
                return .string(value, line: startLine)
            }
            if source[index] == "\n" {
                line += 1
            }
            value.append(source[index])
            advance()
        }
        return .string(value, line: startLine)
    }

    private func startsWith(_ text: String) -> Bool {
        source[index...].hasPrefix(text)
    }

    private func peek() -> Character? {
        let next = source.index(after: index)
        guard next < source.endIndex else { return nil }
        return source[next]
    }

    private mutating func advance() {
        guard index < source.endIndex else { return }
        index = source.index(after: index)
    }

    private func isWordStart(_ character: Character) -> Bool {
        character == "_" || character.isLetter
    }

    private func isWordContinuation(_ character: Character) -> Bool {
        character == "_" || character.isLetter || character.isNumber
    }
}
