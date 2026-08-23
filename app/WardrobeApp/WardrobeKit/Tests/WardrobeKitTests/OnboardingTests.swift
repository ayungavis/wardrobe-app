import Foundation
import Testing
@testable import WardrobeKit

struct AppleAccountTests {
    private static let one = UUID.v7()
    private static let two = UUID.v7()

    @Test func aLaterSignInWithoutNameOrEmailKeepsWhatAppleGaveOnce() {
        let first = AppleAccount(accountID: Self.one, fullName: "Ada Lovelace", email: "ada@example.com")

        let merged = first.merged(with: AppleAccount(accountID: Self.one))

        #expect(merged.fullName == "Ada Lovelace")
        #expect(merged.email == "ada@example.com")
    }

    @Test func newerDetailsWin() {
        let first = AppleAccount(accountID: Self.one, fullName: "Ada", email: nil)

        let merged = first.merged(
            with: AppleAccount(accountID: Self.one, fullName: "Ada L.", email: "ada@example.com")
        )

        #expect(merged.fullName == "Ada L.")
        #expect(merged.email == "ada@example.com")
    }

    @Test func aDifferentAppleUserReplacesTheStoredOneOutright() {
        let first = AppleAccount(accountID: Self.one, fullName: "Ada", email: "ada@example.com")

        let merged = first.merged(with: AppleAccount(accountID: Self.two))

        #expect(merged.accountID == Self.two)
        #expect(merged.fullName == nil)
        #expect(merged.email == nil)
    }
}

@MainActor
struct OnboardingModelTests {
    @MainActor private struct Setup {
        let model: OnboardingModel
        let accounts: StoredAppleAccountRepository
        let store: InMemorySecureStore
        let preferences: InMemoryAccountPreferencesRepository
        let session: FakeSessionService

        init() {
            store = InMemorySecureStore()
            accounts = StoredAppleAccountRepository(store: store)
            preferences = InMemoryAccountPreferencesRepository()
            session = FakeSessionService()
            model = OnboardingModel(
                preferences: preferences, accounts: accounts, session: session
            )
        }
    }

    @Test func itReadsWhatWasStoredBefore() {
        let preferences = InMemoryAccountPreferencesRepository()
        preferences.stored = AccountPreferences(hasCompletedOnboarding: true)

        let model = OnboardingModel(
            preferences: preferences,
            accounts: StoredAppleAccountRepository(store: InMemorySecureStore()),
            session: FakeSessionService()
        )

        #expect(model.isCompleted)
    }

    @Test func skippingFinishesWithoutAnAccount() {
        let setup = Setup()

        setup.model.skip()

        #expect(setup.model.isCompleted)
        #expect(setup.preferences.stored.hasCompletedOnboarding)
        #expect(setup.model.isSignedIn == false)
    }

    @Test func signingInStoresTheAccountTheServerNamedAndFinishes() async throws {
        let setup = Setup()
        let profile = AppleProfile(fullName: "Ada", email: "ada@example.com")

        try await setup.model.signIn(identityToken: "jwt", nonce: "raw", profile: profile)

        #expect(setup.session.linkedWith?.identityToken == "jwt")
        #expect(setup.session.linkedWith?.nonce == "raw")
        #expect(setup.accounts.load()?.accountID == setup.session.linkedAccountID)
        #expect(setup.accounts.load()?.fullName == "Ada")
        #expect(setup.model.isSignedIn)
        #expect(setup.model.isCompleted)
        #expect(setup.preferences.stored.hasCompletedOnboarding)
    }

    @Test func aSecondSignInDoesNotEraseTheStoredNameAndEmail() async throws {
        let setup = Setup()
        try await setup.model.signIn(
            identityToken: "jwt",
            nonce: "raw",
            profile: AppleProfile(fullName: "Ada", email: "ada@example.com")
        )

        try await setup.model.signIn(
            identityToken: "jwt",
            nonce: "raw2",
            profile: AppleProfile(fullName: nil, email: nil)
        )

        #expect(setup.accounts.load()?.fullName == "Ada")
        #expect(setup.accounts.load()?.email == "ada@example.com")
    }

    @Test func resettingSignsOutAndReopensOnboarding() async throws {
        let setup = Setup()
        try await setup.model.signIn(
            identityToken: "jwt", nonce: "raw", profile: AppleProfile(fullName: nil, email: nil)
        )

        try await setup.model.reset()

        #expect(setup.model.isCompleted == false)
        #expect(setup.preferences.stored.hasCompletedOnboarding == false)
        #expect(setup.accounts.load() == nil)
        #expect(setup.model.isSignedIn == false)
        #expect(setup.session.signedOut)
    }

    @Test func aKeychainThatRefusesTheWriteFinishesNothing() async {
        let setup = Setup()
        setup.store.saveError = .unexpected

        await #expect(throws: AppError.unexpected) {
            try await setup.model.signIn(
                identityToken: "jwt",
                nonce: "raw",
                profile: AppleProfile(fullName: nil, email: nil)
            )
        }
        #expect(setup.model.isCompleted == false)
        #expect(setup.preferences.stored.hasCompletedOnboarding == false)
    }

    @Test func aRejectedIdentityTokenFinishesNothing() async {
        let setup = Setup()
        setup.session.linkError = .serverRejected

        await #expect(throws: AppError.serverRejected) {
            try await setup.model.signIn(
                identityToken: "forged",
                nonce: "raw",
                profile: AppleProfile(fullName: nil, email: nil)
            )
        }
        #expect(setup.accounts.load() == nil)
        #expect(setup.model.isCompleted == false)
        #expect(setup.preferences.stored.hasCompletedOnboarding == false)
    }
}

@MainActor
struct OnboardingViewModelTests {
    @MainActor private struct Setup {
        let model: OnboardingViewModel
        let onboarding: OnboardingModel
        let accounts: StoredAppleAccountRepository
        let store: InMemorySecureStore
        let preferences: InMemoryAccountPreferencesRepository
        let session: FakeSessionService

        init() {
            store = InMemorySecureStore()
            accounts = StoredAppleAccountRepository(store: store)
            preferences = InMemoryAccountPreferencesRepository()
            session = FakeSessionService()
            onboarding = OnboardingModel(
                preferences: preferences, accounts: accounts, session: session
            )
            model = OnboardingViewModel(onboarding: onboarding)
        }
    }

    @Test func itStartsAtTheFirstStepWithNoWayBack() {
        let model = Setup().model

        #expect(model.step == .wardrobe)
        #expect(model.canGoBack == false)
        #expect(model.isLastStep == false)
    }

    @Test func nextAndBackWalkTheSteps() {
        let model = Setup().model

        model.next()
        #expect(model.step == .collage)
        #expect(model.canGoBack)

        model.next()
        #expect(model.step == .firstChallenge)
        #expect(model.isLastStep)

        model.next()
        #expect(model.step == .firstChallenge)

        model.back()
        #expect(model.step == .collage)
    }

    @Test func skipAsksBeforeItFinishes() {
        let setup = Setup()
        setup.model.next()
        setup.model.next()

        setup.model.skip()

        #expect(setup.model.isSkipConfirmationPresented)
        #expect(setup.onboarding.isCompleted == false)
        #expect(setup.preferences.stored.hasCompletedOnboarding == false)
    }

    @Test func cancellingTheDialogLeavesTheUserOnTheLastStep() {
        let setup = Setup()
        setup.model.next()
        setup.model.next()
        setup.model.skip()

        setup.model.isSkipConfirmationPresented = false

        #expect(setup.model.step == .firstChallenge)
        #expect(setup.onboarding.isCompleted == false)
    }

    @Test func confirmingTheDialogFinishesWithoutAnAccount() {
        let setup = Setup()
        setup.model.skip()

        setup.model.confirmSkip()

        #expect(setup.model.isSkipConfirmationPresented == false)
        #expect(setup.onboarding.isCompleted)
        #expect(setup.accounts.load() == nil)
    }

    @Test func theNonceGoesToAppleHashedAndToTheServerRaw() async {
        let setup = Setup()
        let hashed = setup.model.beginSignIn()

        await setup.model.signedIn(
            identityToken: "jwt", profile: AppleProfile(fullName: "Ada", email: nil)
        )

        let raw = try? #require(setup.session.linkedWith?.nonce)
        #expect(SignInNonce.hashed(raw ?? "") == hashed)
        #expect(raw != hashed)
        #expect(setup.accounts.load()?.accountID == setup.session.linkedAccountID)
        #expect(setup.onboarding.isCompleted)
    }

    @Test func aCompletionWithoutARequestNeverReachesTheServer() async {
        let setup = Setup()

        await setup.model.signedIn(
            identityToken: "jwt", profile: AppleProfile(fullName: nil, email: nil)
        )

        #expect(setup.session.linkedWith == nil)
        #expect(setup.model.alertError == .unexpected)
        #expect(setup.onboarding.isCompleted == false)
    }

    @Test func aRejectedTokenFinishesNothingAndSurfacesTheError() async {
        let setup = Setup()
        setup.session.linkError = .serverRejected
        _ = setup.model.beginSignIn()

        await setup.model.signedIn(
            identityToken: "forged", profile: AppleProfile(fullName: nil, email: nil)
        )

        #expect(setup.onboarding.isCompleted == false)
        #expect(setup.preferences.stored.hasCompletedOnboarding == false)
        #expect(setup.model.alertError == .serverRejected)
    }

    @Test func aFailedSignInLeavesTheUserWhereTheyWere() {
        let setup = Setup()
        setup.model.next()
        setup.model.next()

        setup.model.signInFailed(AppError.unexpected)

        #expect(setup.model.step == .firstChallenge)
        #expect(setup.onboarding.isCompleted == false)
    }
}
