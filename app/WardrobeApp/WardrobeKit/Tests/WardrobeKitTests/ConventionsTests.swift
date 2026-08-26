import Foundation
import Testing

private let appRoot = URL(filePath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

// ponytail: Tests/ is out of scope. Its 548 `///` lines predate this guard and
// cleaning them is its own decision; widen `scannedRoots` when that decision lands.
private let scannedRoots = [
    appRoot.appending(path: "WardrobeKit/Sources"),
    appRoot.appending(path: "WardrobeApp"),
]

private struct SourceFile {
    let path: String
    let name: String
    let lines: [String]
}

private func sources() throws -> [SourceFile] {
    let manager = FileManager.default
    return try scannedRoots.flatMap { root -> [SourceFile] in
        guard let walker = manager.enumerator(atPath: root.path()) else { return [] }
        return try walker.compactMap { entry -> SourceFile? in
            guard let relative = entry as? String, relative.hasSuffix(".swift"),
                  !relative.contains(".build/")
            else {
                return nil
            }
            let file = root.appending(path: relative)
            let source = try String(contentsOf: file, encoding: .utf8)
            return SourceFile(
                path: "\(root.lastPathComponent)/\(relative)",
                name: file.lastPathComponent,
                lines: source.components(separatedBy: "\n")
            )
        }
    }
}

private let allowedPrefixes = ["// swiftlint:", "// MARK:", "// ponytail:"]

private let httpVerbs = ["GET", "POST", "PUT", "PATCH", "DELETE"]

private func isVerbAndPathLine(_ comment: String) -> Bool {
    let words = comment.split(separator: " ").map(String.init)
    guard words.count == 3, words[0] == "///", httpVerbs.contains(words[1]) else { return false }
    return words[2].hasPrefix("/")
}

private let unsafeOperations = ["try!", "as!", "@unchecked", "nonisolated(unsafe)"]

private func needsRationale(_ line: String) -> Bool {
    if unsafeOperations.contains(where: line.contains) {
        return true
    }
    let characters = Array(line)
    for (index, character) in characters.enumerated() where character == "!" && index > 0 {
        let before = characters[index - 1]
        let after = index + 1 < characters.count ? characters[index + 1] : " "
        if before.isLetter || before.isNumber || before == ")" || before == "]", after != "=" {
            return true
        }
    }
    return false
}

private struct CommentBlock {
    let start: Int
    let lines: [String]
    let next: String?
}

private func commentBlocks(in file: SourceFile) -> [CommentBlock] {
    var blocks: [CommentBlock] = []
    var index = 0
    while index < file.lines.count {
        guard file.lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("//") else {
            index += 1
            continue
        }

        let start = index
        var body: [String] = []
        while index < file.lines.count {
            let trimmed = file.lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("//") else { break }
            body.append(trimmed)
            index += 1
        }

        let next = file.lines[index...].first { line in
            !line.trimmingCharacters(in: .whitespaces).isEmpty
        }
        blocks.append(CommentBlock(start: start, lines: body, next: next))
    }
    return blocks
}

private func isAllowed(_ block: CommentBlock, in file: SourceFile) -> Bool {
    guard let opening = block.lines.first else { return true }
    if allowedPrefixes.contains(where: opening.hasPrefix) {
        return true
    }
    let isLoneEndpointLine = block.lines.count == 1 && isVerbAndPathLine(opening)
    if file.name.hasSuffix("Endpoint.swift"), isLoneEndpointLine {
        return true
    }
    return block.next.map(needsRationale) ?? false
}

private let typeKeywords: Set<String> = ["struct", "class", "enum"]

private let modifiers: Set<String> = ["public", "internal", "private", "fileprivate", "final"]

private func backgroundArguments(in source: String) -> [Substring] {
    var arguments: [Substring] = []
    var search = source.startIndex

    while let opening = source.range(of: ".background(", range: search ..< source.endIndex) {
        var depth = 1
        var index = opening.upperBound
        while index < source.endIndex, depth > 0 {
            switch source[index] {
            case "(": depth += 1
            case ")": depth -= 1
            default: break
            }
            index = source.index(after: index)
        }
        arguments.append(source[opening.upperBound ..< index])
        search = index
    }
    return arguments
}

private func colonOutsideGenerics(in head: Substring) -> Substring.Index? {
    var depth = 0
    for index in head.indices {
        switch head[index] {
        case "<": depth += 1
        case ">": depth -= 1
        case ":" where depth == 0: return index
        default: continue
        }
    }
    return nil
}

private func declaredViewType(in line: String) -> String? {
    guard let head = line.split(separator: "{", maxSplits: 1).first,
          let colon = colonOutsideGenerics(in: head)
    else {
        return nil
    }

    var words = head[..<colon].split(whereSeparator: \.isWhitespace).map(String.init)
    while let first = words.first, modifiers.contains(first) {
        words.removeFirst()
    }
    guard words.count == 2, typeKeywords.contains(words[0]) else { return nil }

    let conformances = head[head.index(after: colon)...]
        .split(whereSeparator: { $0 == "," || $0.isWhitespace })
        .map(String.init)
    guard conformances.contains("View") else { return nil }
    return String(words[1].prefix { $0 != "<" })
}

private func viewTypes(in file: SourceFile) -> [String] {
    file.lines.compactMap(declaredViewType)
}

struct ConventionsTests {
    @Test func noCommentEscapesTheFiveAllowedKinds() throws {
        let offenders = try sources().flatMap { file in
            commentBlocks(in: file)
                .filter { !isAllowed($0, in: file) }
                .flatMap { block in
                    block.lines.enumerated().map { offset, line in
                        "\(file.path):\(block.start + offset + 1) \(line)"
                    }
                }
        }

        #expect(
            offenders.isEmpty,
            """
            Comments under app/** are limited to swiftlint:, MARK:, ponytail:, a rationale \
            beside an unsafe operation, and one verb-and-path line per *Endpoint.swift. \
            \(offenders.count) other comment lines:
            \(offenders.joined(separator: "\n"))
            """
        )
    }

    /// C4: a store file declares stores and storage entities, nothing else. A
    /// domain-shaped value defined inside `Core/Stores/` is a repository concern
    /// wearing the wrong address, and the domain layer ends up importing it.
    @Test func storeFilesDeclareOnlyStoresAndEntities() throws {
        var offenders: [String] = []
        for file in try sources() where file.path.contains("/Core/Stores/") {
            for (index, line) in file.lines.enumerated() {
                guard let name = Self.declaredType(on: line) else { continue }
                if !name.hasSuffix("Store"), !name.hasSuffix("Entity") {
                    offenders.append("\(file.name):\(index + 1) declares \(name)")
                }
            }
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }

    @Test func glassEffectIsNeverBuriedInABackgroundShape() throws {
        for file in try sources() {
            let source = file.lines.joined(separator: "\n")
            for argument in backgroundArguments(in: source) where argument.contains("glassEffect") {
                Issue.record(
                    """
                    \(file.path) applies glassEffect to a shape inside .background(...). \
                    The glass then samples its own backdrop and loses it when the hierarchy is \
                    rebuilt — dismissing a sheet leaves the bare rim behind. Apply \
                    .glassEffect(_:in:) to the content instead.
                    """
                )
            }
        }
    }

    /// C5: every file under `Core/Services/` is `<Name>Service.swift`, per the
    /// layout table. No exceptions.
    @Test func serviceFilesAreNamedService() throws {
        var offenders: [String] = []
        for file in try sources() where file.path.contains("/Core/Services/") {
            guard !file.name.hasSuffix("Service.swift") else { continue }
            offenders.append(file.name)
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }

    private static func declaredType(on line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for keyword in ["struct ", "enum ", "final class ", "class ", "actor "] {
            for access in ["public ", "internal ", ""] {
                let prefix = access + keyword
                if trimmed.hasPrefix(prefix) {
                    let rest = trimmed.dropFirst(prefix.count)
                    return String(rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" })
                }
            }
        }
        return nil
    }

    @Test func everyViewTypeIsNamedView() throws {
        let offenders = try sources().flatMap { file in
            viewTypes(in: file)
                .filter { !$0.hasSuffix("View") }
                .map { "\(file.path): \($0)" }
        }

        #expect(
            offenders.isEmpty,
            """
            Every type conforming to View ends in View. \(offenders.count) do not:
            \(offenders.joined(separator: "\n"))
            """
        )
    }

    @Test func everyFileDeclaringAViewIsNamedViewSwift() throws {
        let offenders = try sources()
            .filter { !viewTypes(in: $0).isEmpty && !$0.name.hasSuffix("View.swift") }
            .map(\.path)

        #expect(
            offenders.isEmpty,
            """
            A file declaring a View is named <Name>View.swift. \(offenders.count) are not:
            \(offenders.joined(separator: "\n"))
            """
        )
    }
}
