import Foundation
import Testing
@testable import WardrobeKit

@MainActor
struct MediaTests {
    // MARK: - The size check has to happen before the network

    @Test func anOversizedObjectIsRefusedBeforeAnyRequestGoesOut() async throws {
        let sut = makeSUT()
        let tooBig = Data(count: MediaKind.original.uploadCap + 1)

        await #expect(throws: AppError.payloadTooLarge) {
            try await sut.repository.upload(tooBig, id: UUID(), kind: .original, contentType: "image/jpeg")
        }

        #expect(sut.client.reserves == 0)
    }

    @Test func anObjectAtTheCapIsAccepted() async throws {
        let sut = makeSUT()
        sut.server.stub("/object", StubbedReply(status: 200))

        try await sut.repository.upload(
            Data(count: 8), id: UUID(), kind: .cutout, contentType: "image/png"
        )

        #expect(sut.client.reserves == 1)
    }

    // MARK: - Caps must not drift from the server

    @Test func everyCapMatchesTheServersUploadCap() {
        #expect(MediaKind.original.uploadCap == 25 * 1024 * 1024)
        #expect(MediaKind.derivative.uploadCap == 10 * 1024 * 1024)
        #expect(MediaKind.illustration.uploadCap == 10 * 1024 * 1024)
        #expect(MediaKind.cutout.uploadCap == 5 * 1024 * 1024)
        #expect(MediaKind.history.uploadCap == 5 * 1024 * 1024)
        #expect(MediaKind.document.uploadCap == 2 * 1024 * 1024)
    }

    @Test func everyKindTheServerKnowsHasACase() {
        let server = ["original", "derivative", "cutout", "illustration", "document", "history"]

        #expect(MediaKind.allCases.map(\.rawValue).sorted() == server.sorted())
    }

    // MARK: - Reading by identity

    @Test func aCachedObjectIsReturnedWithoutAskingForAGrant() async throws {
        let sut = makeSUT()
        let id = UUID()
        try sut.cache.store(Data("kept".utf8), for: id)

        let read = try await sut.repository.data(for: id)

        #expect(read == Data("kept".utf8))
        #expect(sut.client.grants == 0)
    }

    @Test func aMissingObjectIsFetchedThroughAFreshGrant() async throws {
        let sut = makeSUT()
        sut.server.stub("/object", StubbedReply(status: 200, body: Data("downloaded".utf8)))

        let read = try await sut.repository.data(for: UUID())

        #expect(read == Data("downloaded".utf8))
        #expect(sut.client.grants == 1)
    }

    @Test func anExpiredUrlIsRefreshedRatherThanTreatedAsMissing() async throws {
        let sut = makeSUT()
        let id = UUID()
        sut.server.stub("/object", StubbedReply(status: 200, body: Data("first".utf8)))

        _ = try await sut.repository.data(for: id)
        try sut.cache.removeAll()
        sut.server.stub("/object", StubbedReply(status: 200, body: Data("second".utf8)))
        let again = try await sut.repository.data(for: id)

        #expect(again == Data("second".utf8))
        #expect(sut.client.grants == 2)
    }

    // MARK: - A signed URL never reaches disk

    @Test func nothingWrittenToTheCacheLooksLikeASignedUrl() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "media-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sut = makeSUT(cache: FileMediaCacheStore(directory: directory))
        sut.server.stub("/object", StubbedReply(status: 200, body: Data("bytes".utf8)))

        try await sut.repository.upload(
            Data("bytes".utf8), id: UUID(), kind: .cutout, contentType: "image/png"
        )

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path())
        #expect(!files.isEmpty)
        for file in files {
            let written = try Data(contentsOf: directory.appending(path: file))
            let text = String(bytes: written, encoding: .utf8) ?? ""
            #expect(!text.contains("http"), "a signed URL must never be written to disk")
        }
    }

    // MARK: - Fixtures

    private struct SUT {
        let repository: ServerMediaRepository
        let client: StubGrantClient
        let cache: any MediaCacheStore
        let server: StubServer
    }

    private func makeSUT(cache: (any MediaCacheStore)? = nil) -> SUT {
        let server = StubServer()
        let client = StubGrantClient(objectURL: "https://objects.invalid/object")
        let store = cache ?? InMemoryMediaCacheStore()
        return SUT(
            repository: ServerMediaRepository(client: client, cache: store, session: server.session),
            client: client, cache: store, server: server
        )
    }
}

// MARK: - Doubles

@MainActor
private final class StubGrantClient: AuthenticatedAPIClient {
    private(set) var reserves = 0
    private(set) var grants = 0
    private let objectURL: String

    init(objectURL: String) {
        self.objectURL = objectURL
    }

    func send<Route: Endpoint>(_ endpoint: Route) async throws -> Route.Response {
        guard endpoint is GetMediaIdEndpoint else { throw AppError.unexpected }
        grants += 1
        return try decodeGrant()
    }

    func send<Route: RequestEndpoint>(_ endpoint: Route) async throws -> Route.Response {
        guard endpoint is PostMediaEndpoint else { throw AppError.unexpected }
        reserves += 1
        return try decodeGrant()
    }

    private func decodeGrant<Value: Decodable>() throws -> Value {
        let json = #"""
        {"mediaId":"\#(UUID().uuidString.lowercased())","url":"\#(objectURL)",
         "expiresAt":"2026-08-25T04:00:00Z","byteSize":null}
        """#
        return try JSONDecoder.api.decode(Value.self, from: Data(json.utf8))
    }
}
