import Foundation
import Observation

@MainActor
@Observable
public final class DevMenuViewModel {
    public private(set) var summary = DevStateSummary()
    public private(set) var lastAction: String?
    private(set) var sessionState: Loadable<DevSessionInfo> = .idle
    private(set) var sessionTask: Task<Void, Never>?
    private(set) var healthState: Loadable<String> = .idle
    private(set) var healthTask: Task<Void, Never>?
    private(set) var outbox: [OutboxEnvelope] = []
    private(set) var cursor: Int64 = 0
    private(set) var pullState: Loadable<PullOutcome> = .idle
    private(set) var pullTask: Task<Void, Never>?

    private let activeRepository: ActiveChallengeRepository
    private let completedRepository: CompletedChallengeRepository
    private let photoRepository: PhotoRepository
    private let wardrobeRepository: WardrobeItemRepository
    private let thumbnails: GarmentThumbnailRepository
    private let previews: CompletionPreviewRepository
    private let onboarding: OnboardingModel
    private let session: any SessionService
    private let client: any AuthenticatedAPIClient
    private let plainClient: any APIClient
    let baseURL: URL
    private let tokens: any SessionTokenRepository
    private let outboxRepository: any OutboxRepository
    private let feed: any ChangeFeedRepository
    private let calendar: Calendar

    init(
        activeRepository: ActiveChallengeRepository,
        completedRepository: CompletedChallengeRepository,
        photoRepository: PhotoRepository,
        wardrobeRepository: WardrobeItemRepository,
        thumbnails: GarmentThumbnailRepository,
        previews: CompletionPreviewRepository,
        onboarding: OnboardingModel,
        session: any SessionService,
        client: any AuthenticatedAPIClient,
        plainClient: any APIClient,
        baseURL: URL,
        tokens: any SessionTokenRepository,
        outboxRepository: any OutboxRepository,
        feed: any ChangeFeedRepository,
        calendar: Calendar = .current
    ) {
        self.activeRepository = activeRepository
        self.completedRepository = completedRepository
        self.photoRepository = photoRepository
        self.wardrobeRepository = wardrobeRepository
        self.thumbnails = thumbnails
        self.previews = previews
        self.onboarding = onboarding
        self.session = session
        self.client = client
        self.plainClient = plainClient
        self.baseURL = baseURL
        self.tokens = tokens
        self.outboxRepository = outboxRepository
        self.feed = feed
        self.calendar = calendar
    }

    func checkHealth() {
        healthTask?.cancel()
        healthState = .loading

        healthTask = Task { [plainClient] in
            do {
                let response = try await plainClient.send(GetHealthEndpoint())
                try Task.checkCancellation()
                healthState = .loaded(response.status)
            } catch is CancellationError {
            } catch {
                Log.report(error, logger: Log.network)
                healthState = .failed(AppError(wrapping: error))
            }
        }
    }

    func loadSession(callingWhoami: Bool = false) {
        sessionTask?.cancel()
        sessionState = .loading

        sessionTask = Task {
            do {
                _ = try await session.accessToken()
                try Task.checkCancellation()

                let whoami: DevSessionInfo.Whoami?
                if callingWhoami {
                    let response = try await client.send(GetWhoamiEndpoint())
                    try Task.checkCancellation()
                    whoami = DevSessionInfo.Whoami(
                        accountID: response.accountId, sessionID: response.sessionId
                    )
                } else {
                    whoami = nil
                }

                guard let stored = tokens.load() else {
                    sessionState = .failed(.sessionExpired)
                    return
                }
                sessionState = .loaded(DevSessionInfo(
                    accountID: stored.accountID,
                    accessExpiresAt: stored.expiresAt,
                    refreshExpiresAt: stored.refreshExpiresAt,
                    isAccessUsable: stored.isUsable(at: .now),
                    whoami: whoami
                ))
            } catch is CancellationError {
            } catch {
                Log.report(error, logger: Log.network)
                sessionState = .failed(AppError(wrapping: error))
            }
        }
    }

    public func refresh() {
        outbox = (try? outboxRepository.entries()) ?? []
        cursor = (try? feed.position()) ?? 0
        let active = activeRepository.load()
        summary = DevStateSummary(
            completionCount: completedRepository.load().count,
            hasCompletedToday: completedRepository.hasCompletion(on: Date(), calendar: calendar),
            hasActiveChallenge: active != nil,
            activeHasPhoto: active?.photoID != nil,
            wardrobeItemCount: (try? wardrobeRepository.items().count) ?? 0,
            fingerprintCount: (try? wardrobeRepository.fingerprints().count) ?? 0,
            hasCompletedOnboarding: onboarding.isCompleted,
            isSignedIn: onboarding.isSignedIn
        )
    }

    public func resetOnboarding() async {
        do {
            try await onboarding.reset()
            Log.ui.info("Dev: onboarding reset")
        } catch {
            Log.report(error)
        }
        refresh()
        lastAction = "Onboarding reset"
    }

    public func resetWardrobe() {
        do {
            try wardrobeRepository.deleteAll()
            try thumbnails.deleteAll()
            Log.ui.info("Dev: wardrobe reset")
        } catch {
            Log.report(error)
        }
        refresh()
        lastAction = "Wardrobe cleared"
    }

    public func resetToday() {
        let today = Date()

        let todaysCompletions = completedRepository.load()
            .filter { calendar.isDate($0.completedAt, inSameDayAs: today) }
        for completion in todaysCompletions {
            photoRepository.deleteOriginals(of: completion.document, and: completion.photoID)
            deletePreview(of: completion)
        }
        completedRepository.removeCompletions(on: today)

        if let active = activeRepository.load() {
            photoRepository.deleteOriginals(of: active.document, and: active.photoID)
            photoRepository.deleteUnusedOriginals(
                of: active.document, imported: active.importedPhotoIDs
            )
        }
        activeRepository.clear()

        refresh()
        lastAction = "Today's challenge reset"
        Log.ui.info("Dev: today's challenge reset")
    }

    public func resetHistory() {
        for completion in completedRepository.load() {
            photoRepository.deleteOriginals(of: completion.document, and: completion.photoID)
        }
        do {
            try previews.deleteAll()
        } catch {
            Log.report(error)
        }
        completedRepository.removeAll()

        refresh()
        lastAction = "History cleared"
        Log.ui.info("Dev: history cleared")
    }

    func pullChanges() {
        pullTask?.cancel()
        pullState = .loading

        pullTask = Task { [feed] in
            do {
                let outcome = try await feed.pull(applying: NoopChangeApplier())
                try Task.checkCancellation()
                pullState = .loaded(outcome)
            } catch is CancellationError {
            } catch {
                Log.report(error, logger: Log.network)
                pullState = .failed(AppError(wrapping: error))
            }
            refresh()
        }
    }

    public func retryFailedOutbox() {
        do {
            try outboxRepository.retryFailed(at: Date())
        } catch {
            Log.report(error)
        }
        refresh()
        lastAction = "Outbox retry requested"
    }

    public func clearOutbox() {
        do {
            try outboxRepository.removeAll()
        } catch {
            Log.report(error)
        }
        refresh()
        lastAction = "Outbox cleared"
    }

    private func deletePreview(of completion: CompletedChallenge) {
        guard let file = completion.previewFile else { return }
        do {
            try previews.delete(file: file)
        } catch {
            Log.report(error)
        }
    }
}
