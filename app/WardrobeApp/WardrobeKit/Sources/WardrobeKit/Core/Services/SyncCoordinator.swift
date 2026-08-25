import Foundation

enum SyncTrigger: String, Sendable, CaseIterable {
    case foreground
    case tabOpened
    case signedIn
    case connectivityRestored
    case manual
}

struct ReconcileOutcome: Sendable, Equatable {
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
protocol SyncCoordinator: AnyObject {
    func reconcile(_ trigger: SyncTrigger) async -> ReconcileOutcome
}

@MainActor
final class ServerSyncCoordinator: SyncCoordinator {
    private let client: any AuthenticatedAPIClient
    private let outbox: any OutboxRepository
    private let feed: any ChangeFeedRepository
    private let applier: any ChangeApplier
    private var inFlight: Task<ReconcileOutcome, Never>?

    init(
        client: any AuthenticatedAPIClient,
        outbox: any OutboxRepository,
        feed: any ChangeFeedRepository,
        applier: any ChangeApplier = NoopChangeApplier()
    ) {
        self.client = client
        self.outbox = outbox
        self.feed = feed
        self.applier = applier
    }

    func reconcile(_ trigger: SyncTrigger) async -> ReconcileOutcome {
        Log.network.info("Reconciling: \(trigger.rawValue, privacy: .public)")
        if let running = inFlight {
            return await running.value
        }

        let work = Task { await run() }
        inFlight = work
        defer { inFlight = nil }
        return await work.value
    }

    private func run() async -> ReconcileOutcome {
        var outcome = ReconcileOutcome()

        do {
            let sent = try await push()
            outcome.pushed = sent.pushed
            outcome.rejected = sent.rejected
            outcome.pushError = sent.error
        } catch {
            Log.report(error, logger: Log.network)
            outcome.pushError = AppError(wrapping: error)
        }

        do {
            outcome.pulled = try await feed.pull(applying: applier).records
        } catch {
            Log.report(error, logger: Log.network)
            outcome.pullError = AppError(wrapping: error)
        }

        return outcome
    }

    private func push() async throws -> PushOutcome {
        let due = try outbox.due(at: Date(), limit: SyncBatching.maxMutations)
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
