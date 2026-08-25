import Foundation

// ponytail: the applier speaks in DTOs because nothing maps the twelve kinds to
// domain types yet — T45 owns that and will know which ones it needs. It must
// write through the store's own ModelContext and never save; the cursor's save
// is what makes the page and its position land together.
@MainActor
protocol ChangeApplier: AnyObject {
    func apply(_ changes: [ChangeDTO]) throws
}

struct PullOutcome: Sendable, Equatable {
    let pages: Int
    let records: Int
    let position: Int64
}

@MainActor
protocol ChangeFeedRepository: AnyObject {
    func position() throws -> Int64
    func pull(limit: Int, applying applier: any ChangeApplier) async throws -> PullOutcome
}

extension ChangeFeedRepository {
    func pull(applying applier: any ChangeApplier) async throws -> PullOutcome {
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

    func pull(limit: Int, applying applier: any ChangeApplier) async throws -> PullOutcome {
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

// ponytail: T38 reads the feed and moves the cursor; nothing applies yet. T45
// replaces this with the real restore, which is the ticket that knows which
// kinds it needs and what a conflict with a local edit means.
@MainActor
final class NoopChangeApplier: ChangeApplier {
    func apply(_: [ChangeDTO]) throws {}
}
