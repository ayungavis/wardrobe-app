import AVFoundation
import DesignSystem
import SwiftUI

public struct CaptureFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: CaptureFlowViewModel
    private let makeEditorViewModel: (ActiveChallenge) -> EditorViewModel

    public init(
        viewModel: CaptureFlowViewModel,
        makeEditorViewModel: @escaping (ActiveChallenge) -> EditorViewModel
    ) {
        _viewModel = State(wrappedValue: viewModel)
        self.makeEditorViewModel = makeEditorViewModel
    }

    public var body: some View {
        @Bindable var viewModel = viewModel

        Group {
            switch viewModel.stage {
            case .consent:
                ConsentStageView(
                    onContinue: { viewModel.consentContinue() },
                    onNotNow: { dismiss() }
                )
            case .denied:
                DeniedStageView(onClose: { dismiss() })
            case .camera:
                CameraStageView(viewModel: viewModel, onClose: { dismiss() })
            case .editor:
                EditorView(
                    viewModel: makeEditorViewModel(viewModel.challenge),
                    onDiscard: { viewModel.discardPhoto() }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.background)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                viewModel.recheckPermission()
            }
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
}

/// FR-013: plain-language explanation BEFORE the system camera prompt.
private struct ConsentStageView: View {
    let onContinue: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            Image(systemName: "camera")
                .font(.system(size: 56))
                .foregroundStyle(AppColor.accent)

            Text("capture.consent.title", bundle: .module)
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)

            Text("capture.consent.message", bundle: .module)
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)

            Spacer()

            PrimaryButton(Text("capture.consent.continue", bundle: .module), action: onContinue)

            Button(action: onNotNow) {
                Text("capture.consent.notNow", bundle: .module)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(Spacing.xl)
    }
}

/// FR-014: denied/restricted — settings guidance + safe return.
private struct DeniedStageView: View {
    @Environment(\.openURL) private var openURL
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            Image(systemName: "camera.badge.ellipsis")
                .font(.system(size: 56))
                .foregroundStyle(AppColor.textSecondary)

            Text("capture.denied.title", bundle: .module)
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)

            Text("capture.denied.message", bundle: .module)
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)

            Spacer()

            #if os(iOS)
                PrimaryButton(Text("capture.denied.openSettings", bundle: .module)) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            #endif

            Button(action: onClose) {
                Text("common.close", bundle: .module)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(Spacing.xl)
    }
}

/// Round translucent control used on top of media, story-editor style.
struct MediaCircleButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColor.onMedia)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .environment(\.colorScheme, .dark)
        }
    }
}
