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
struct OnboardingViewModelTests {
    @MainActor private struct Setup {
        let model: OnboardingViewModel
        let accounts: InMemoryAppleAccountRepository
        let preferences: InMemoryAccountPreferencesRepository

        init() {
            accounts = InMemoryAppleAccountRepository()
            preferences = InMemoryAccountPreferencesRepository()
            model = OnboardingViewModel(
                accountRepository: accounts, preferencesRepository: preferences
            )
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
        let model = setup.model
        let preferences = setup.preferences
        model.next()
        model.next()

        model.skip()

        #expect(model.isSkipConfirmationPresented)
        #expect(model.isCompleted == false)
        #expect(preferences.stored.hasCompletedOnboarding == false)
    }

    @Test func cancellingTheDialogLeavesTheUserOnTheLastStep() {
        let setup = Setup()
        let model = setup.model
        let preferences = setup.preferences
        model.next()
        model.next()
        model.skip()

        model.isSkipConfirmationPresented = false

        #expect(model.step == .firstChallenge)
        #expect(model.isCompleted == false)
        #expect(preferences.stored.hasCompletedOnboarding == false)
    }

    @Test func confirmingTheDialogFinishesWithoutAnAccount() {
        let setup = Setup()
        let model = setup.model
        let accounts = setup.accounts
        let preferences = setup.preferences
        model.skip()

        model.confirmSkip()

        #expect(model.isSkipConfirmationPresented == false)
        #expect(model.isCompleted)
        #expect(preferences.stored.hasCompletedOnboarding)
        #expect(accounts.stored == nil)
    }

    @Test func signingInStoresTheAccountAndFinishes() {
        let setup = Setup()
        let model = setup.model
        let accounts = setup.accounts
        let preferences = setup.preferences
        let account = AppleAccount(userID: "u1", fullName: "Ada", email: "ada@example.com")

        model.signedIn(account)

        #expect(accounts.stored == account)
        #expect(model.isCompleted)
        #expect(preferences.stored.hasCompletedOnboarding)
    }

    /// Onboarding is the only gate in front of the app: finishing it on a failed
    /// save would leave the user inside with no identity and no way back.
    @Test func aFailedSaveFinishesNothingAndSurfacesTheError() {
        let setup = Setup()
        let model = setup.model
        let accounts = setup.accounts
        let preferences = setup.preferences
        accounts.saveError = .unexpected

        model.signedIn(AppleAccount(userID: "u1"))

        #expect(model.isCompleted == false)
        #expect(preferences.stored.hasCompletedOnboarding == false)
        #expect(model.alertError == .unexpected)
    }

    @Test func aFailedSignInLeavesTheUserWhereTheyWere() {
        let setup = Setup()
        let model = setup.model
        let preferences = setup.preferences
        model.next()
        model.next()

        model.signInFailed(AppError.unexpected)

        #expect(model.step == .firstChallenge)
        #expect(model.isCompleted == false)
        #expect(preferences.stored.hasCompletedOnboarding == false)
    }
}
