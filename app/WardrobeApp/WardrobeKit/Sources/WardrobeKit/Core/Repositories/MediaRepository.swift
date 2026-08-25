import Foundation

@MainActor
public protocol MediaRepository: AnyObject {
    func upload(_ data: Data, id: UUID, kind: MediaKind, contentType: String) async throws
    func data(for id: UUID) async throws -> Data
    func clearCache() throws
}

@MainActor
public final class ServerMediaRepository: MediaRepository {
    private let client: any AuthenticatedAPIClient
    private let cache: any MediaCacheStore
    private let session: URLSession

    public init(
        client: any AuthenticatedAPIClient,
        cache: any MediaCacheStore,
        session: URLSession = .shared
    ) {
        self.client = client
        self.cache = cache
        self.session = session
    }

    // ponytail: checked here because the server's enforcement is detective, not
    // preventive — a presigned PUT cannot sign Content-Length, so an oversized
    // object uploads fine and is discarded later, object and row together.
    public static let maxContentType = 100

    public func upload(_ data: Data, id: UUID, kind: MediaKind, contentType: String) async throws {
        guard data.count <= kind.uploadCap else { throw AppError.payloadTooLarge }
        guard !contentType.isEmpty, contentType.count <= Self.maxContentType else {
            throw AppError.badRequest
        }

        let grant = try await client.send(PostMediaEndpoint(request: PostMediaRequestDTO(
            mediaId: id,
            kind: kind.rawValue,
            contentType: contentType,
            byteSize: Int64(data.count)
        )))

        try await put(data, to: grant, contentType: contentType)
        try cache.store(data, for: id)
    }

    public func data(for id: UUID) async throws -> Data {
        if let cached = cache.data(for: id) {
            return cached
        }

        let grant = try await client.send(GetMediaIdEndpoint(id: id))
        let downloaded = try await fetch(grant)
        try cache.store(downloaded, for: id)
        return downloaded
    }

    public func clearCache() throws {
        try cache.removeAll()
    }

    // ponytail: this leaves APIClient behind on purpose. The grant points at the
    // object store, not the API base URL, and its Content-Type is part of what
    // was signed — sending a different one is refused by the store.
    private func put(_ data: Data, to grant: MediaGrantDTO, contentType: String) async throws {
        guard let url = URL(string: grant.url) else { throw AppError.serverRejected }
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.put.rawValue
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        let (_, response) = try await session.upload(for: request, from: data)
        try Self.check(response, endpoint: "media.put", id: grant.mediaId)
    }

    private func fetch(_ grant: MediaGrantDTO) async throws -> Data {
        guard let url = URL(string: grant.url) else { throw AppError.serverRejected }

        let (data, response) = try await session.data(from: url)
        try Self.check(response, endpoint: "media.get", id: grant.mediaId)
        return data
    }

    private static func check(_ response: URLResponse, endpoint: String, id: UUID) throws {
        guard let http = response as? HTTPURLResponse else { throw AppError.network }
        guard (200 ..< 300).contains(http.statusCode) else {
            let failure = AppError.serverRejected
            Log.trail(failure, context: Log.Context(
                operation: endpoint, endpoint: id.uuidString, status: http.statusCode
            ))
            throw failure
        }
    }
}
