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
            case let .preview(data):
                PreviewStageView(
                    data: data,
                    onRetake: { viewModel.retake() },
                    onUse: { viewModel.usePhoto(data) }
                )
            case .editor:
                EditorView(viewModel: makeEditorViewModel(viewModel.challenge))
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

/// FR-015/016: story-style full-screen camera — dark, big shutter ring,
/// flip button. Live preview on device, placeholder on simulator/macOS.
private struct CameraStageView: View {
    let viewModel: CaptureFlowViewModel
    let onClose: () -> Void

    var body: some View {
        ZStack {
            AppColor.mediaBackground.ignoresSafeArea()

            if let session = viewModel.previewSession {
                #if os(iOS)
                    CameraPreviewView(session: session)
                        .ignoresSafeArea()
                #endif
            } else {
                // Simulator / sample camera: no live feed.
                VStack(spacing: Spacing.md) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 72))
                    Text("capture.camera.samplePlaceholder", bundle: .module)
                        .font(AppFont.caption)
                }
                .foregroundStyle(AppColor.onMedia.opacity(0.6))
            }

            VStack {
                HStack {
                    MediaCircleButton(systemName: "xmark", action: onClose)
                        .accessibilityLabel(Text("common.close", bundle: .module))
                    Spacer()
                }
                Spacer()

                ZStack {
                    Button {
                        viewModel.capture()
                    } label: {
                        Circle()
                            .strokeBorder(AppColor.onMedia, lineWidth: 5)
                            .frame(width: 80, height: 80)
                            .overlay(Circle().fill(AppColor.onMedia.opacity(0.35)).padding(8))
                    }
                    .disabled(viewModel.isCapturing)
                    .accessibilityLabel(Text("capture.camera.capture", bundle: .module))

                    HStack {
                        Spacer()
                        MediaCircleButton(systemName: "arrow.triangle.2.circlepath.camera") {
                            viewModel.flipCamera()
                        }
                        .accessibilityLabel(Text("capture.camera.flip", bundle: .module))
                    }
                }
            }
            .padding(Spacing.xl)
        }
        .sensoryFeedback(.impact, trigger: viewModel.isCapturing) { _, new in new }
        .task {
            viewModel.cameraAppeared()
        }
        .onDisappear {
            viewModel.cameraDisappeared()
        }
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

/// FR-016: preview with retake / use photo — story-style dark.
private struct PreviewStageView: View {
    let data: Data
    let onRetake: () -> Void
    let onUse: () -> Void

    var body: some View {
        VStack(spacing: Spacing.xl) {
            DownsampledPhotoView(data: data)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(.rect(cornerRadius: 16))

            HStack(spacing: Spacing.lg) {
                Button(action: onRetake) {
                    Text("capture.preview.retake", bundle: .module)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)

                PrimaryButton(Text("capture.preview.usePhoto", bundle: .module), action: onUse)
            }
        }
        .padding(Spacing.xl)
        .background(AppColor.mediaBackground.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }
}
