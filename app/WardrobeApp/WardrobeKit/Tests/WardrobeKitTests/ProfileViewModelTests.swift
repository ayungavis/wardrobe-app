import Foundation
import SwiftData
import Testing
@testable import WardrobeKit

@MainActor
struct ProfileViewModelTests {
    // MARK: - Sign-out (FR-055)

    @Test func signOutWithPendingWritesWarnsInsteadOfProceeding() async throws {
        let sut = try makeSUT()
        try sut.outbox.enqueue(SyncMutation.deleteItem(DeleteItemArgsDTO(id: UUID())).queued(), at: Date())

        await sut.viewModel.requestSignOut()

        #expect(sut.viewModel.isSignOutWarningPresented)
        #expect(!sut.session.signedOut, "credentials go only after pending writes are handled")
        #expect(sut.purge.purgeCount == 0)
    }

    @Test func signOutKeepsTheAnonymousIdentityAndClearsTokens() async throws {
        let sut = try makeSUT()
        try sut.accounts.save(AppleAccount(accountID: UUID(), fullName: "A", email: nil))
        let identityBefore = try sut.session.identity()

        await sut.viewModel.requestSignOut()

        #expect(sut.session.signedOut)
        #expect(sut.accounts.load() == nil)
        #expect(try sut.session.identity() == identityBefore)
        #expect(sut.purge.purgeCount == 1)
        #expect(sut.viewModel.didFinish)
    }

    @Test func discardingPendingWritesEmptiesBothQueuesThenSignsOut() async throws {
        let sut = try makeSUT()
        try sut.outbox.enqueue(SyncMutation.deleteItem(DeleteItemArgsDTO(id: UUID())).queued(), at: Date())
        await sut.viewModel.requestSignOut()
        #expect(sut.viewModel.isSignOutWarningPresented)

        await sut.viewModel.signOutDiscardingPendingWrites()

        #expect(try sut.outbox.entries().isEmpty)
        #expect(sut.session.signedOut)
        #expect(sut.viewModel.didFinish)
    }

    // MARK: - Deletion (FR-071)

    @Test func aFailedDeletionLeavesLocalDataIntactAndRetryable() async throws {
        let sut = try makeSUT()
        sut.accountService.error = .unavailable

        await sut.viewModel.deleteAccount()

        #expect(sut.purge.purgeCount == 0, "503 means retry, not purge")
        #expect(!sut.session.signedOut)
        #expect(sut.viewModel.isDeletionRetryable)
        #expect(!sut.viewModel.didFinish)
        #expect(sut.viewModel.alertError == .unavailable)
    }

    @Test func localPurgeHappensOnlyAfterTheServerConfirms() async throws {
        let sut = try makeSUT()

        await sut.viewModel.deleteAccount()

        #expect(sut.accountService.calls == 1)
        #expect(sut.purge.purgeCount == 1)
        #expect(sut.session.signedOut)
        #expect(!sut.viewModel.isDeletionRetryable)
        #expect(sut.viewModel.didFinish)
        #expect(sut.defaults.object(forKey: ProfileViewModel.deletionRequestedKey) == nil)
    }

    @Test func aRetryAfterFailureCanSucceed() async throws {
        let sut = try makeSUT()
        sut.accountService.error = .unavailable
        await sut.viewModel.deleteAccount()
        #expect(sut.viewModel.isDeletionRetryable)

        sut.accountService.error = nil
        await sut.viewModel.deleteAccount()

        #expect(sut.purge.purgeCount == 1)
        #expect(sut.viewModel.didFinish)
    }

    // MARK: - Fixtures

    private struct SUT {
        let viewModel: ProfileViewModel
        let session: FakeSessionService
        let accounts: StoredAppleAccountRepository
        let outbox: StoredOutboxRepository
        let purge: RecordingPurgeService
        let accountService: StubAccountService
        let defaults: UserDefaults
    }

    private func makeSUT() throws -> SUT {
        let container = try ModelContainer(
            for: SwiftDataWardrobeItemRepository.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let outbox = StoredOutboxRepository(store: SwiftDataOutboxStore(context: context))
        let uploads = makeInMemoryUploads()
        let session = FakeSessionService()
        let accounts = StoredAppleAccountRepository(store: InMemorySecureStore())
        let onboarding = OnboardingModel(
            preferences: InMemoryAccountPreferencesRepository(),
            accounts: accounts,
            session: session
        )
        let purge = RecordingPurgeService()
        let accountService = StubAccountService()
        let suite = "profile-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let viewModel = ProfileViewModel(
            accounts: accounts,
            onboarding: onboarding,
            outbox: outbox,
            uploads: uploads,
            purge: purge,
            accountService: accountService,
            defaults: defaults,
            syncNow: {}
        )
        return SUT(
            viewModel: viewModel, session: session, accounts: accounts,
            outbox: outbox, purge: purge, accountService: accountService, defaults: defaults
        )
    }
}

@MainActor
final class RecordingPurgeService: PurgeService {
    private(set) var purgeCount = 0

    func purgeAccountData() throws {
        purgeCount += 1
    }
}

final class StubAccountService: AccountService, @unchecked Sendable {
    // @unchecked: tests drive it from one actor at a time.
    var error: AppError?
    private(set) var calls = 0

    func deleteAccount() async throws {
        calls += 1
        if let error {
            throw error
        }
    }
}
