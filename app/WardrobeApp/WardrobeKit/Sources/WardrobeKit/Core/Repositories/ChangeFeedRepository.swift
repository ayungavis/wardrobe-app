import Foundation

struct PullOutcome: Sendable, Equatable {
    let pages: Int
    let records: Int
    let position: Int64
}

@MainActor
protocol ChangeFeedRepository: AnyObject {
    func position() throws -> Int64
    func pull(limit: Int, applying applier: any RestoreService) async throws -> PullOutcome
}

extension ChangeFeedRepository {
    func pull(applying applier: any RestoreService) async throws -> PullOutcome {
        try await pull(limit: ServerChangeFeedRepository.defaultLimit, applying: applier)
    }
}

@MainActor
final class ServerChangeFeedRepository: ChangeFeedRepository {
    static let defaultLimit = 500

    private let client: any AuthenticatedAPIClient
    private let cursor: any CursorStore

    init(client: any AuthenticatedAPIClient, cursor: any CursorStore) {
        self.client = client
        self.cursor = cursor
    }

    func position() throws -> Int64 {
        try cursor.position()
    }

    func pull(limit: Int, applying applier: any RestoreService) async throws -> PullOutcome {
        var since = try cursor.position()
        var pages = 0
        var records = 0

        while true {
            try Task.checkCancellation()
            let page = try await client.send(GetChangesEndpoint(since: since, limit: limit))
            pages += 1

            guard page.nextSince != since else {
                return PullOutcome(pages: pages, records: records, position: since)
            }

            do {
                try applier.apply(page.changes)
                try cursor.stage(position: page.nextSince)
                try cursor.commit()
            } catch {
                cursor.discard()
                throw error
            }

            records += page.changes.count
            since = page.nextSince
        }
    }
}
