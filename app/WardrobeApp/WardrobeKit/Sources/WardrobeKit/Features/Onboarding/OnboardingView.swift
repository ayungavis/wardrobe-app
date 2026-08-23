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
            Spacer(minLength: 0)

            OnboardingStepView(step: viewModel.step) {
                actions
            }
            .id(viewModel.step)
            .transition(.opacity)
            .animation(.snappy, value: viewModel.step)

            progress
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 20).onEnded { value in
                switch OnboardingSwipe.direction(for: value.translation) {
                case .next: viewModel.next()
                case .back: viewModel.back()
                case nil: break
                }
            }
        )
        .alert(
            Text("onboarding.skip.title", bundle: .module),
            isPresented: $viewModel.isSkipConfirmationPresented
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
                    request.nonce = viewModel.beginSignIn()
                } onCompletion: { result in
                    handle(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 45)
                .disabled(viewModel.isSigningIn)
                .accessibilityIdentifier("onboarding.signIn")

                HStack {
                    if viewModel.canGoBack {
                        Button(action: viewModel.back) {
                            Text("onboarding.back", bundle: .module)
                                .font(AppFont.body)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                        .accessibilityIdentifier("onboarding.back")
                    }
                    Spacer()
                    Button(action: viewModel.skip) {
                        Text("onboarding.skip", bundle: .module)
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    .accessibilityIdentifier("onboarding.skip")
                }
            } else {
                HStack {
                    if viewModel.canGoBack {
                        Button(action: viewModel.back) {
                            Text("onboarding.back", bundle: .module)
                                .font(AppFont.body)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                        .accessibilityIdentifier("onboarding.back")
                    } else {
                        Spacer().frame(width: 1)
                    }
                    Spacer()
                    PrimaryButtonView(Text("onboarding.next", bundle: .module), action: viewModel.next)
                        .fixedSize()
                        .accessibilityIdentifier("onboarding.next")
                }
            }
        }
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let token = credential.identityToken,
                  let identityToken = String(data: token, encoding: .utf8)
            else {
                viewModel.signInFailed(AppError.unexpected)
                return
            }
            let profile = AppleProfile(
                fullName: credential.fullName?.formatted(.name(style: .medium)),
                email: credential.email
            )
            Task { await viewModel.signedIn(identityToken: identityToken, profile: profile) }
        case let .failure(error):
            viewModel.signInFailed(error)
        }
    }
}
