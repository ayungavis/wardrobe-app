import Foundation
import Observation

@MainActor
@Observable
public final class ProfileViewModel {
    private(set) var account: AppleAccount?
    private(set) var pendingWrites = 0
    var isSignOutWarningPresented = false
    var isDeleteConfirmationPresented = false
    private(set) var isDeleting = false
    private(set) var isDeletionRetryable = false
    private(set) var didFinish = false
    var alertError: AppError?

    static let deletionRequestedKey = "accountDeletionRequestedAt"

    private let accounts: AppleAccountRepository
    private let onboarding: OnboardingModel
    private let outbox: any OutboxRepository
    private let uploads: any MediaUploadRepository
    private let purge: PurgeService
    private let accountService: AccountService
    private let defaults: UserDefaults
    private let syncNow: () async -> Void

    public init(
        accounts: AppleAccountRepository,
        onboarding: OnboardingModel,
        outbox: any OutboxRepository,
        uploads: any MediaUploadRepository,
        purge: PurgeService,
        accountService: AccountService,
        defaults: UserDefaults = .standard,
        syncNow: @escaping () async -> Void
    ) {
        self.accounts = accounts
        self.onboarding = onboarding
        self.outbox = outbox
        self.uploads = uploads
        self.purge = purge
        self.accountService = accountService
        self.defaults = defaults
        self.syncNow = syncNow
    }

    public var isSignedIn: Bool {
        account != nil
    }

    public func load() {
        account = accounts.load()
        pendingWrites = ((try? outbox.entries()) ?? []).count + ((try? uploads.entries()) ?? []).count
        isDeletionRetryable = defaults.object(forKey: Self.deletionRequestedKey) != nil
    }

    public func requestSignOut() async {
        load()
        guard pendingWrites == 0 else {
            isSignOutWarningPresented = true
            return
        }
        await performSignOut()
    }

    public func syncPendingWrites() async {
        await syncNow()
        load()
    }

    public func signOutDiscardingPendingWrites() async {
        do {
            try outbox.removeAll()
            try uploads.removeAll()
        } catch {
            alertError = AppError(wrapping: error)
            return
        }
        await performSignOut()
    }

    public func requestDeletion() {
        isDeleteConfirmationPresented = true
    }

    public func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }
        defaults.set(Date(), forKey: Self.deletionRequestedKey)
        isDeletionRetryable = true
        do {
            try await accountService.deleteAccount()
            try purge.purgeAccountData()
            try await onboarding.reset()
            defaults.removeObject(forKey: Self.deletionRequestedKey)
            isDeletionRetryable = false
            didFinish = true
            Log.ui.info("Account deleted; local state purged")
        } catch {
            alertError = AppError(wrapping: error)
        }
    }

    private func performSignOut() async {
        do {
            try purge.purgeAccountData()
            try await onboarding.reset()
            didFinish = true
            Log.ui.info("Signed out on this device")
        } catch {
            alertError = AppError(wrapping: error)
        }
    }
}
