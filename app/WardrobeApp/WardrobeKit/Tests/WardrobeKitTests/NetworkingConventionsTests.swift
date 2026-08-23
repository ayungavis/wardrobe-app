import Foundation
import Testing

private let endpointsRoot = URL(filePath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appending(path: "Sources/WardrobeKit/Core/Networking/Endpoints")

private struct EndpointFolder {
    let name: String
    let files: [String]
    let source: [String: String]

    var endpointFile: String {
        "\(name)Endpoint.swift"
    }

    var requestFile: String {
        "\(name)RequestDTO.swift"
    }

    var responseFile: String {
        "\(name)ResponseDTO.swift"
    }
}

private func folders() throws -> [EndpointFolder] {
    let manager = FileManager.default
    let children = try manager.contentsOfDirectory(atPath: endpointsRoot.path())
        .filter { !$0.hasPrefix(".") }
        .sorted()

    return try children.map { name in
        let directory = endpointsRoot.appending(path: name)
        var isDirectory: ObjCBool = false
        #expect(
            manager.fileExists(atPath: directory.path(), isDirectory: &isDirectory)
                && isDirectory.boolValue,
            "\(name) sits directly under Endpoints/; every endpoint gets its own folder"
        )

        let files = try manager.contentsOfDirectory(atPath: directory.path())
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        let source = try files.reduce(into: [String: String]()) { store, file in
            store[file] = try String(contentsOf: directory.appending(path: file), encoding: .utf8)
        }
        return EndpointFolder(name: name, files: files, source: source)
    }
}

private func declarations(in source: String) -> [String] {
    source.split(separator: "\n").compactMap { line in
        let words = line.split(separator: " ").map(String.init)
        guard let keyword = words.first, ["struct", "enum", "typealias"].contains(keyword),
              let name = words.dropFirst().first
        else {
            return nil
        }
        return name.prefix { $0.isLetter || $0.isNumber }.description
    }
}

private func commentLines(in source: String) -> [String] {
    source.split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { $0.hasPrefix("//") }
}

struct NetworkingConventionsTests {
    @Test func everyEndpointFolderCarriesItsEndpointFile() throws {
        for folder in try folders() {
            #expect(
                folder.files.contains(folder.endpointFile),
                "\(folder.name) has no \(folder.endpointFile)"
            )
            #expect(
                folder.files.contains(folder.responseFile),
                "\(folder.name) has no \(folder.responseFile); every endpoint decodes something"
            )
        }
    }

    @Test func noOtherFileNameIsAllowedInsideAnEndpointFolder() throws {
        for folder in try folders() {
            let allowed = [folder.endpointFile, folder.requestFile, folder.responseFile]
            for file in folder.files {
                #expect(
                    allowed.contains(file),
                    "\(folder.name)/\(file) is not one of the three names the rule allows"
                )
            }
        }
    }

    @Test func aRequestFileExistsExactlyWhenTheEndpointConformsToRequestEndpoint() throws {
        for folder in try folders() {
            let carriesRequest = folder.source[folder.endpointFile]?
                .contains(": RequestEndpoint") == true
            #expect(
                folder.files.contains(folder.requestFile) == carriesRequest,
                """
                \(folder.name): the endpoint conforms to \
                \(carriesRequest ? "RequestEndpoint" : "Endpoint") but \
                \(folder.files.contains(folder.requestFile) ? "has" : "has no") \(folder.requestFile)
                """
            )
        }
    }

    @Test func everyTypeInADTOFileEndsInDTO() throws {
        for folder in try folders() {
            for file in folder.files where file.hasSuffix("DTO.swift") {
                for declared in declarations(in: folder.source[file] ?? "") {
                    #expect(
                        declared.hasSuffix("DTO"),
                        "\(folder.name)/\(file) declares \(declared), which does not end in DTO"
                    )
                }
            }
        }
    }

    @Test func anEndpointFileCarriesOneLineNamingItsVerbAndPath() throws {
        let shape = /^\/\/\/ (GET|POST|PUT|PATCH|DELETE) \/\S+$/

        for folder in try folders() {
            let comments = commentLines(in: folder.source[folder.endpointFile] ?? "")
            #expect(
                comments.count == 1,
                """
                \(folder.name)/\(folder.endpointFile) has \(comments.count) comment lines; \
                exactly one is allowed and it names the verb and path
                """
            )
            guard let only = comments.first else { continue }
            #expect(
                only.wholeMatch(of: shape) != nil,
                """
                \(folder.name)/\(folder.endpointFile) starts with "\(only)"; the one allowed \
                line reads like `/// POST /v1/sessions/apple`
                """
            )
        }
    }

    @Test func aDTOFileCarriesNoComments() throws {
        for folder in try folders() {
            for file in folder.files where file.hasSuffix("DTO.swift") {
                let comments = commentLines(in: folder.source[file] ?? "")
                #expect(
                    comments.isEmpty,
                    "\(folder.name)/\(file) carries \(comments.count) comment lines; DTO files carry none"
                )
            }
        }
    }
}
