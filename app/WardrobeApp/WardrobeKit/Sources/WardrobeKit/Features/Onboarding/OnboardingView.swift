import AuthenticationServices
import DesignSystem
import SwiftUI

public struct OnboardingView: View {
    @State private var viewModel: OnboardingViewModel

    public init(viewModel: OnboardingViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    public var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: Spacing.xl) {
            progress

            Spacer()

            OnboardingStepView(step: viewModel.step)
                .id(viewModel.step)
                .transition(.opacity)

            Spacer()

            actions
        }
        .padding(Spacing.xl)
        .animation(.snappy, value: viewModel.step)
        .confirmationDialog(
            Text("onboarding.skip.title", bundle: .module),
            isPresented: $viewModel.isSkipConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                viewModel.confirmSkip()
            } label: {
                Text("onboarding.skip.action", bundle: .module)
            }
            Button(role: .cancel) {} label: {
                Text("common.cancel", bundle: .module)
            }
        } message: {
            Text("onboarding.skip.message", bundle: .module)
        }
        .alert(
            Text("common.errorTitle", bundle: .module),
            isPresented: Binding(
                get: { viewModel.alertError != nil },
                set: {
                    if !$0 {
                        viewModel.alertError = nil
                    }
                }
            )
        ) {
            Button(role: .cancel) {} label: { Text("common.ok", bundle: .module) }
        } message: {
            Text(viewModel.alertError?.userMessage ?? "")
        }
    }

    private var progress: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Capsule()
                    .fill(step == viewModel.step ? AppColor.accent : AppColor.textSecondary.opacity(0.25))
                    .frame(width: step == viewModel.step ? 24 : 8, height: 8)
            }
        }
        .accessibilityHidden(true)
    }

    private var actions: some View {
        VStack(spacing: Spacing.md) {
            if viewModel.isLastStep {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handle(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 54)
                .accessibilityIdentifier("onboarding.signIn")

                Button(action: viewModel.skip) {
                    Text("onboarding.skip", bundle: .module)
                        .font(AppFont.body)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("onboarding.skip")
            } else {
                PrimaryButtonView(Text("onboarding.next", bundle: .module), action: viewModel.next)
                    .accessibilityIdentifier("onboarding.next")
            }

            if viewModel.canGoBack {
                Button(action: viewModel.back) {
                    Text("onboarding.back", bundle: .module)
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("onboarding.back")
            }
        }
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                viewModel.signInFailed(AppError.unexpected)
                return
            }
            viewModel.signedIn(AppleAccount(
                userID: credential.user,
                fullName: credential.fullName?.formatted(.name(style: .medium)),
                email: credential.email
            ))
        case let .failure(error):
            viewModel.signInFailed(error)
        }
    }
}
