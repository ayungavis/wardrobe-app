import Foundation

enum SyncTrigger: String, Sendable, CaseIterable {
    case foreground
    case tabOpened
    case signedIn
    case connectivityRestored
    case manual
}

struct ReconcileOutcome: Sendable, Equatable {
    var uploaded = 0
    var pushed = 0
    var rejected = 0
    var pulled = 0
    var pushError: AppError?
    var pullError: AppError?
}

private struct PushOutcome {
    var pushed = 0
    var rejected = 0
    var error: AppError?
}

@MainActor
protocol SyncService: AnyObject {
    func reconcile(_ trigger: SyncTrigger) async -> ReconcileOutcome
}

@MainActor
final class ServerSyncService: SyncService {
    private let client: any AuthenticatedAPIClient
    private let outbox: any OutboxRepository
    private let feed: any ChangeFeedRepository
    private let uploads: any MediaUploadRepository
    private let media: any MediaRepository
    private let preferences: any AccountPreferencesRepository
    private let applier: any ChangeApplier
    private var inFlight: Task<ReconcileOutcome, Never>?

    init(
        client: any AuthenticatedAPIClient,
        outbox: any OutboxRepository,
        feed: any ChangeFeedRepository,
        uploads: any MediaUploadRepository,
        media: any MediaRepository,
        preferences: any AccountPreferencesRepository,
        applier: any ChangeApplier = NoopChangeApplier()
    ) {
        self.client = client
        self.outbox = outbox
        self.feed = feed
        self.uploads = uploads
        self.media = media
        self.preferences = preferences
        self.applier = applier
    }

    func reconcile(_ trigger: SyncTrigger) async -> ReconcileOutcome {
        Log.network.info("Reconciling: \(trigger.rawValue, privacy: .public)")
        if let running = inFlight {
            return await running.value
        }

        let work = Task { await run(trigger) }
        inFlight = work
        defer { inFlight = nil }
        return await work.value
    }

    private func run(_ trigger: SyncTrigger) async -> ReconcileOutcome {
        var outcome = ReconcileOutcome()

        let sent = await uploadDueMedia()
        outcome.uploaded = sent.uploaded
        if let fatal = sent.fatal {
            outcome.pushError = fatal
            outcome.pullError = fatal
            return outcome
        }

        do {
            let sent = try await push()
            outcome.pushed = sent.pushed
            outcome.rejected = sent.rejected
            outcome.pushError = sent.error
        } catch {
            Log.report(
                error,
                context: Log.Context(operation: "sync.push.\(trigger.rawValue)"),
                logger: Log.network
            )
            outcome.pushError = AppError(wrapping: error)
        }

        do {
            outcome.pulled = try await feed.pull(applying: applier).records
        } catch {
            Log.report(
                error,
                context: Log.Context(operation: "sync.pull.\(trigger.rawValue)"),
                logger: Log.network
            )
            outcome.pullError = AppError(wrapping: error)
        }

        return outcome
    }

    private func uploadDueMedia() async -> (uploaded: Int, fatal: AppError?) {
        // ponytail: §18 rule 4 — no byte leaves the device before the disclosure is
        // accepted. Held rows also hold their completeChallenge through T37c's
        // ownership rule, so the canvas text waits with its media for free.
        guard preferences.load().uploadConsentAt != nil else { return (0, nil) }

        let due = (try? uploads.due(at: Date(), limit: SyncBatching.maxMutations)) ?? []
        var uploaded = 0

        for row in due {
            do {
                let bytes = try uploads.bytes(for: row)
                try await media.upload(bytes, id: row.id, kind: row.kind, contentType: row.contentType)
                try uploads.acknowledge(id: row.id)
                uploaded += 1
            } catch is CancellationError {
                return (uploaded, nil)
            } catch AppError.sessionExpired {
                return (uploaded, .sessionExpired)
            } catch {
                let failure = AppError(wrapping: error)
                Log.report(
                    failure,
                    context: Log.Context(operation: "sync.upload.\(row.kind.rawValue)"),
                    logger: Log.network
                )
                try? uploads.recordFailure(of: row.id, error: failure, code: nil, at: Date())
            }
        }
        return (uploaded, nil)
    }

    private func push() async throws -> PushOutcome {
        // ponytail: a completeChallenge whose media rows still exist would only be
        // rejected by the server's foreign keys, so it waits — held back by
        // ownership, not by name. An unreadable queue holds it back too, because
        // pushing on a guess spends attempts on a certain rejection.
        let due = try outbox.due(at: Date(), limit: SyncBatching.maxMutations)
            .filter { entry in
                entry.name != SyncMutation.completeChallengeName || ((try? uploads.holdsRows(owner: entry.id)) ?? true) == false
            }
        guard !due.isEmpty else { return PushOutcome() }

        let decoder = JSONDecoder.api
        let requests = try due.map { envelope in
            try MutationRequestDTO(
                id: envelope.id,
                name: envelope.name,
                args: decoder.decode(JSONValue.self, from: envelope.payload)
            )
        }

        var outcome = PushOutcome()
        for batch in try SyncBatching.batches(from: requests) {
            let settled = try await send(batch)
            outcome.pushed += settled.pushed
            outcome.rejected += settled.rejected
            outcome.error = outcome.error ?? settled.error
        }
        return outcome
    }

    private func send(_ batch: [MutationRequestDTO]) async throws -> PushOutcome {
        let response: PostSyncResponseDTO
        do {
            response = try await client.send(
                PostSyncEndpoint(request: PostSyncRequestDTO(mutations: batch))
            )
        } catch AppError.sessionExpired {
            // ponytail: SessionedAPIClient already refreshed once. A second failure is
            // the session's fault, not the mutation's, so nothing here spends an
            // attempt — otherwise one expired session burns every entry's five at once.
            throw AppError.sessionExpired
        } catch {
            let failure = AppError(wrapping: error)
            for mutation in batch {
                try outbox.recordFailure(of: mutation.id, error: failure, at: Date())
            }
            return PushOutcome(pushed: 0, rejected: batch.count, error: failure)
        }

        var outcome = PushOutcome()
        for result in response.results {
            switch result.outcome {
            case .applied:
                try outbox.acknowledge(id: result.id)
                outcome.pushed += 1
            case let .failed(detail):
                try outbox.recordFailure(
                    of: result.id, error: .serverRejected, code: detail.code, at: Date()
                )
                outcome.rejected += 1
            }
        }
        return outcome
    }
}
