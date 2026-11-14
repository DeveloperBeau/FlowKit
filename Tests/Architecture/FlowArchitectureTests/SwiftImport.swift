/// An `import` declaration found in a Swift source file.
struct SwiftImport: Equatable, Sendable {
    var moduleName: String
    var line: Int
    /// Path relative to the package root. Empty when the source was a string.
    var file: String

    /// Import declarations in `source`.
    ///
    /// Comments and string literals are ignored, so a note that mentions
    /// `import` is not a dependency. The module name is the first component
    /// of the import path.
    static func scan(_ source: String) -> [SwiftImport] {
        let blanked = SourceBlanker.blank(source)
        return ImportParser.scan(blanked)
    }
}

/// Replaces comments and string contents with spaces.
///
/// Newlines stay where they are, so a later line number still matches the file.
private enum SourceBlanker {
    static func blank(_ source: String) -> [Character] {
        var chars = Array(source)
        var index = 0
        blankCode(&chars, &index, stopAtParen: false)
        return chars
    }

    private static func blankCode(
        _ chars: inout [Character],
        _ index: inout Int,
        stopAtParen: Bool
    ) {
        var parenDepth = 0
        while index < chars.count {
            let character = chars[index]
            if stopAtParen && character == ")" && parenDepth == 0 {
                return
            }
            if character == "/" && look(chars, index + 1) == "/" {
                while index < chars.count && chars[index] != "\n" {
                    chars[index] = " "
                    index += 1
                }
                continue
            }
            if character == "/" && look(chars, index + 1) == "*" {
                blankBlock(&chars, &index)
                continue
            }
            if character == "#" {
                let hashes = hashRun(chars, index)
                if hashes > 0,
                   index + hashes < chars.count,
                   chars[index + hashes] == "\"" {
                    blankRaw(&chars, &index, hashes: hashes)
                    continue
                }
            }
            if character == "\"" {
                blankPlainString(&chars, &index)
                continue
            }
            if character == "(" {
                parenDepth += 1
                index += 1
                continue
            }
            if character == ")" {
                if parenDepth > 0 {
                    parenDepth -= 1
                }
                index += 1
                continue
            }
            index += 1
        }
    }

    private static func blankBlock(_ chars: inout [Character], _ index: inout Int) {
        chars[index] = " "
        chars[index + 1] = " "
        index += 2
        var depth = 1
        while index < chars.count && depth > 0 {
            if chars[index] == "/" && look(chars, index + 1) == "*" {
                chars[index] = " "
                chars[index + 1] = " "
                index += 2
                depth += 1
                continue
            }
            if chars[index] == "*" && look(chars, index + 1) == "/" {
                chars[index] = " "
                chars[index + 1] = " "
                index += 2
                depth -= 1
                continue
            }
            if chars[index] != "\n" {
                chars[index] = " "
            }
            index += 1
        }
    }

    private static func blankPlainString(_ chars: inout [Character], _ index: inout Int) {
        let multiline = isTripleQuote(chars, index)
        let opening = multiline ? 3 : 1
        for _ in 0..<opening {
            chars[index] = " "
            index += 1
        }
        while index < chars.count {
            if !multiline && chars[index] == "\n" {
                return
            }
            if chars[index] == "\\" {
                chars[index] = " "
                index += 1
                if index >= chars.count {
                    return
                }
                if chars[index] == "(" {
                    chars[index] = " "
                    index += 1
                    blankCode(&chars, &index, stopAtParen: true)
                    if index < chars.count && chars[index] == ")" {
                        chars[index] = " "
                        index += 1
                    }
                    continue
                }
                if chars[index] != "\n" {
                    chars[index] = " "
                }
                index += 1
                continue
            }
            if multiline && isTripleQuote(chars, index) {
                chars[index] = " "
                chars[index + 1] = " "
                chars[index + 2] = " "
                index += 3
                return
            }
            if !multiline && chars[index] == "\"" {
                chars[index] = " "
                index += 1
                return
            }
            if chars[index] != "\n" {
                chars[index] = " "
            }
            index += 1
        }
    }

    private static func blankRaw(
        _ chars: inout [Character],
        _ index: inout Int,
        hashes: Int
    ) {
        let multiline = isTripleQuote(chars, index + hashes)
        let opening = hashes + (multiline ? 3 : 1)
        for _ in 0..<opening where index < chars.count {
            if chars[index] != "\n" {
                chars[index] = " "
            }
            index += 1
        }
        while index < chars.count {
            if !multiline && chars[index] == "\n" {
                return
            }
            if chars[index] == "\\" && hashRun(chars, index + 1) == hashes && look(chars, index + 1 + hashes) == "(" {
                let marker = 1 + hashes + 1
                for _ in 0..<marker where index < chars.count {
                    chars[index] = " "
                    index += 1
                }
                blankCode(&chars, &index, stopAtParen: true)
                if index < chars.count && chars[index] == ")" {
                    chars[index] = " "
                    index += 1
                }
                continue
            }
            if chars[index] == "\"" {
                if multiline && isTripleQuote(chars, index) && hashRun(chars, index + 3) >= hashes {
                    let closing = 3 + hashes
                    for _ in 0..<closing where index < chars.count {
                        chars[index] = " "
                        index += 1
                    }
                    return
                }
                if !multiline && hashRun(chars, index + 1) >= hashes {
                    let closing = 1 + hashes
                    for _ in 0..<closing where index < chars.count {
                        chars[index] = " "
                        index += 1
                    }
                    return
                }
            }
            if chars[index] != "\n" {
                chars[index] = " "
            }
            index += 1
        }
    }

    private static func isTripleQuote(_ chars: [Character], _ index: Int) -> Bool {
        index + 2 < chars.count
            && chars[index] == "\""
            && chars[index + 1] == "\""
            && chars[index + 2] == "\""
    }

    private static func hashRun(_ chars: [Character], _ index: Int) -> Int {
        var position = index
        var count = 0
        while position < chars.count && chars[position] == "#" {
            count += 1
            position += 1
        }
        return count
    }

    private static func look(_ chars: [Character], _ index: Int) -> Character? {
        guard index >= 0 && index < chars.count else { return nil }
        return chars[index]
    }
}

/// Finds import declarations in source whose comments and strings are already blanked.
private enum ImportParser {
    private static let modifiers: Set<String> = [
        "private", "fileprivate", "internal", "package", "public", "open"
    ]
    private static let kinds: Set<String> = [
        "typealias", "struct", "class", "enum", "protocol", "let", "var", "func"
    ]

    static func scan(_ chars: [Character]) -> [SwiftImport] {
        var imports: [SwiftImport] = []
        var index = 0
        while index < chars.count {
            if isStatementStart(chars, index), let parsed = parseImport(chars, from: index) {
                imports.append(
                    SwiftImport(
                        moduleName: parsed.module,
                        line: lineNumber(chars, at: parsed.keyword),
                        file: ""
                    )
                )
                index = max(parsed.end, index + 1)
                continue
            }
            if isStatementStart(chars, index) {
                let next = skipRestOfStatement(chars, index)
                index = next > index ? next : index + 1
                continue
            }
            index += 1
        }
        return imports
    }

    private static func parseImport(
        _ chars: [Character],
        from start: Int
    ) -> (module: String, keyword: Int, end: Int)? {
        var index = start
        // Attributes and an access modifier may arrive in either order.
        while true {
            if parseAttribute(chars, &index) {
                continue
            }
            let beforeModifier = index
            skipWhitespace(chars, &index)
            if let word = parseIdentifier(chars, &index), modifiers.contains(word) {
                continue
            }
            index = beforeModifier
            break
        }

        skipWhitespace(chars, &index)
        let keyword = index
        guard consumeKeyword("import", chars, &index) else { return nil }
        skipWhitespace(chars, &index)

        guard let first = parseIdentifier(chars, &index), !first.isEmpty else { return nil }
        let module: String
        if kinds.contains(first) {
            // `import struct Module.Name` names the module after the kind.
            skipWhitespace(chars, &index)
            guard let imported = parseIdentifier(chars, &index), !imported.isEmpty else { return nil }
            module = imported
        } else {
            module = first
        }

        while true {
            let beforeDot = index
            skipWhitespace(chars, &index)
            guard index < chars.count, chars[index] == "." else {
                index = beforeDot
                break
            }
            index += 1
            skipWhitespace(chars, &index)
            guard parseIdentifier(chars, &index) != nil else {
                index = beforeDot
                break
            }
        }
        guard index > start else { return nil }
        return (module, keyword, index)
    }

    private static func parseAttribute(_ chars: [Character], _ index: inout Int) -> Bool {
        var position = index
        skipWhitespace(chars, &position)
        guard position < chars.count, chars[position] == "@" else { return false }
        position += 1
        guard parseIdentifier(chars, &position) != nil else { return false }
        skipWhitespace(chars, &position)
        if position < chars.count, chars[position] == "(" {
            guard skipBalanced(chars, &position, open: "(", close: ")") else { return false }
        }
        index = position
        return true
    }

    private static func consumeKeyword(
        _ keyword: String,
        _ chars: [Character],
        _ index: inout Int
    ) -> Bool {
        let saved = index
        guard parseIdentifier(chars, &index) == keyword else {
            index = saved
            return false
        }
        return true
    }

    private static func parseIdentifier(_ chars: [Character], _ index: inout Int) -> String? {
        guard index < chars.count else { return nil }
        if chars[index] == "`" {
            index += 1
            var name = ""
            while index < chars.count && chars[index] != "`" && chars[index] != "\n" {
                name.append(chars[index])
                index += 1
            }
            guard index < chars.count, chars[index] == "`", !name.isEmpty else { return nil }
            index += 1
            return name
        }
        guard isIdentifierStart(chars[index]) else { return nil }
        var name = ""
        while index < chars.count && isIdentifierContinuation(chars[index]) {
            name.append(chars[index])
            index += 1
        }
        return name
    }

    private static func skipBalanced(
        _ chars: [Character],
        _ index: inout Int,
        open: Character,
        close: Character
    ) -> Bool {
        guard index < chars.count, chars[index] == open else { return false }
        var depth = 0
        while index < chars.count {
            if chars[index] == open {
                depth += 1
            } else if chars[index] == close {
                depth -= 1
                index += 1
                if depth == 0 {
                    return true
                }
                continue
            }
            index += 1
        }
        return false
    }

    private static func skipWhitespace(_ chars: [Character], _ index: inout Int) {
        while index < chars.count {
            let character = chars[index]
            if character == " " || character == "\t" || character == "\n" || character == "\r" {
                index += 1
            } else {
                return
            }
        }
    }

    private static func skipRestOfStatement(_ chars: [Character], _ index: Int) -> Int {
        var position = index
        if position < chars.count {
            let character = chars[position]
            if character == "\n" || character == ";" {
                return position + 1
            }
        }
        while position < chars.count {
            let character = chars[position]
            if character == "\n" || character == ";" {
                return position
            }
            position += 1
        }
        return position
    }

    private static func isStatementStart(_ chars: [Character], _ index: Int) -> Bool {
        var position = index - 1
        while position >= 0 {
            let character = chars[position]
            if character == " " || character == "\t" || character == "\r" {
                position -= 1
                continue
            }
            return character == "\n" || character == ";"
        }
        return true
    }

    private static func lineNumber(_ chars: [Character], at index: Int) -> Int {
        var line = 1
        var position = 0
        let end = min(index, chars.count)
        while position < end {
            if chars[position] == "\n" {
                line += 1
            }
            position += 1
        }
        return line
    }

    private static func isIdentifierStart(_ character: Character) -> Bool {
        character == "_" || character.isLetter
    }

    private static func isIdentifierContinuation(_ character: Character) -> Bool {
        character == "_" || character.isLetter || character.isNumber
    }
}
