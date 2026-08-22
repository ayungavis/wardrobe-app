import AVFoundation
import DesignSystem
import SwiftUI

public struct CaptureFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: CaptureFlowViewModel
    private let makeEditorViewModel: (ActiveChallenge) -> EditorViewModel
    private let makeCropViewModel: (String) -> CropViewModel

    public init(
        viewModel: CaptureFlowViewModel,
        makeEditorViewModel: @escaping (ActiveChallenge) -> EditorViewModel,
        makeCropViewModel: @escaping (String) -> CropViewModel
    ) {
        _viewModel = State(wrappedValue: viewModel)
        self.makeEditorViewModel = makeEditorViewModel
        self.makeCropViewModel = makeCropViewModel
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
                ZStack {
                    CameraStageView(viewModel: viewModel, onClose: { dismiss() })
                    
                    if viewModel.isTipsPresented {
                        TipsStageView(
                            onContinue: { dontShowAgain in viewModel.tipsContinue(dontShowAgain: dontShowAgain) },
                            onClose: { dismiss() }
                        )
                        .transition(.opacity)
                    }
                }
                .animation(.default, value: viewModel.isTipsPresented)
            case .crop:
                cropStage
            case .scanReview:
                ScanReviewView(
                    review: viewModel.review,
                    onRetake: { viewModel.discardPhoto() },
                    onContinue: { viewModel.continueToEditor() }
                )
            case .editor:
                EditorView(
                    viewModel: makeEditorViewModel(viewModel.challenge),
                    isCompleting: viewModel.isCompleting,
                    didResumeDraft: viewModel.didResumeDraft,
                    makeCropViewModel: makeCropViewModel,
                    onDiscard: { viewModel.discardPhoto() },
                    onComplete: { viewModel.completeChallenge() },
//                    reviewDrawer: {
//                        ItemReviewDrawerView(
//                            garments: viewModel.review.garments,
//                            isScanning: viewModel.review.isScanning,
//                            thumbnail: { viewModel.review.thumbnailData(forFile: $0) },
//                            itemThumbnail: { viewModel.review.thumbnailData(forItemID: $0) },
//                            onChoose: { viewModel.review.choose($1, for: $0) }
//                        )
//                    }
                )
                .task { viewModel.review.scanIfNeeded(photoID: viewModel.challenge.photoID) }
                
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.background)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                viewModel.recheckPermission()
            }
        }
        .onChange(of: viewModel.isCompleted) { _, completed in
            if completed {
                dismiss()
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

    @ViewBuilder
    private var cropStage: some View {
        if let photoID = viewModel.challenge.photoID {
            CropView(
                viewModel: makeCropViewModel(photoID),
                aspectRatio: CropGeometry.photoAspectRatio,
                onExit: { viewModel.discardPhoto() },
                onUseCrop: { viewModel.useCrop($0) }
            )
        }
    }
}

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

            PrimaryButtonView(Text("capture.consent.continue", bundle: .module), action: onContinue)

            Button(action: onNotNow) {
                Text("capture.consent.notNow", bundle: .module)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(Spacing.xl)
    }
}

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
                PrimaryButtonView(Text("capture.denied.openSettings", bundle: .module)) {
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



