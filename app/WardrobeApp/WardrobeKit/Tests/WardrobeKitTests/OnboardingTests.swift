import Testing
@testable import WardrobeKit

struct AppleAccountTests {
    @Test func aLaterSignInWithoutNameOrEmailKeepsWhatAppleGaveOnce() {
        let first = AppleAccount(userID: "u1", fullName: "Ada Lovelace", email: "ada@example.com")

        let merged = first.merged(with: AppleAccount(userID: "u1"))

        #expect(merged.fullName == "Ada Lovelace")
        #expect(merged.email == "ada@example.com")
    }

    @Test func newerDetailsWin() {
        let first = AppleAccount(userID: "u1", fullName: "Ada", email: nil)

        let merged = first.merged(with: AppleAccount(userID: "u1", fullName: "Ada L.", email: "ada@example.com"))

        #expect(merged.fullName == "Ada L.")
        #expect(merged.email == "ada@example.com")
    }

    @Test func aDifferentAppleUserReplacesTheStoredOneOutright() {
        let first = AppleAccount(userID: "u1", fullName: "Ada", email: "ada@example.com")

        let merged = first.merged(with: AppleAccount(userID: "u2"))

        #expect(merged.userID == "u2")
        #expect(merged.fullName == nil)
        #expect(merged.email == nil)
    }
}

@MainActor
struct OnboardingModelTests {
    @MainActor private struct Setup {
        let model: OnboardingModel
        let accounts: InMemoryAppleAccountRepository
        let preferences: InMemoryAccountPreferencesRepository

        init() {
            accounts = InMemoryAppleAccountRepository()
            preferences = InMemoryAccountPreferencesRepository()
            model = OnboardingModel(preferences: preferences, accounts: accounts)
        }
    }

    @Test func itReadsWhatWasStoredBefore() {
        let preferences = InMemoryAccountPreferencesRepository()
        preferences.stored = AccountPreferences(hasCompletedOnboarding: true)

        let model = OnboardingModel(
            preferences: preferences, accounts: InMemoryAppleAccountRepository()
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

    @Test func signingInStoresTheAccountAndFinishes() throws {
        let setup = Setup()
        let account = AppleAccount(userID: "u1", fullName: "Ada", email: "ada@example.com")

        try setup.model.signIn(account)

        #expect(setup.accounts.stored == account)
        #expect(setup.model.isSignedIn)
        #expect(setup.model.isCompleted)
        #expect(setup.preferences.stored.hasCompletedOnboarding)
    }

    /// The merge rule has to survive the trip through the model, not just the
    /// domain: Apple sends the name and email exactly once.
    @Test func aSecondSignInDoesNotEraseTheStoredNameAndEmail() throws {
        let setup = Setup()
        try setup.model.signIn(
            AppleAccount(userID: "u1", fullName: "Ada", email: "ada@example.com")
        )

        try setup.model.signIn(AppleAccount(userID: "u1"))

        #expect(setup.accounts.stored?.fullName == "Ada")
        #expect(setup.accounts.stored?.email == "ada@example.com")
    }

    @Test func resettingSignsOutAndReopensOnboarding() throws {
        let setup = Setup()
        try setup.model.signIn(AppleAccount(userID: "u1"))

        try setup.model.reset()

        #expect(setup.model.isCompleted == false)
        #expect(setup.preferences.stored.hasCompletedOnboarding == false)
        #expect(setup.accounts.stored == nil)
        #expect(setup.model.isSignedIn == false)
    }

    @Test func aFailedSaveFinishesNothing() {
        let setup = Setup()
        setup.accounts.saveError = .unexpected

        #expect(throws: AppError.unexpected) {
            try setup.model.signIn(AppleAccount(userID: "u1"))
        }
        #expect(setup.model.isCompleted == false)
        #expect(setup.preferences.stored.hasCompletedOnboarding == false)
    }
}

@MainActor
struct OnboardingViewModelTests {
    @MainActor private struct Setup {
        let model: OnboardingViewModel
        let onboarding: OnboardingModel
        let accounts: InMemoryAppleAccountRepository
        let preferences: InMemoryAccountPreferencesRepository

        init() {
            accounts = InMemoryAppleAccountRepository()
            preferences = InMemoryAccountPreferencesRepository()
            onboarding = OnboardingModel(preferences: preferences, accounts: accounts)
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
        #expect(setup.accounts.stored == nil)
    }

    @Test func signingInStoresTheAccountAndFinishes() {
        let setup = Setup()
        let account = AppleAccount(userID: "u1", fullName: "Ada", email: "ada@example.com")

        setup.model.signedIn(account)

        #expect(setup.accounts.stored == account)
        #expect(setup.onboarding.isCompleted)
    }

    /// Onboarding is the only gate in front of the app: finishing it on a failed
    /// save would leave the user inside with no identity and no way back.
    @Test func aFailedSaveFinishesNothingAndSurfacesTheError() {
        let setup = Setup()
        setup.accounts.saveError = .unexpected

        setup.model.signedIn(AppleAccount(userID: "u1"))

        #expect(setup.onboarding.isCompleted == false)
        #expect(setup.preferences.stored.hasCompletedOnboarding == false)
        #expect(setup.model.alertError == .unexpected)
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
