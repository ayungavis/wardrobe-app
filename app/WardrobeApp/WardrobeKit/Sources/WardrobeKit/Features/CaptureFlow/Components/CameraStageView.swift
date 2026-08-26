import DesignSystem
import SwiftUI

struct CameraStageView: View {
    let viewModel: CaptureFlowViewModel
    let onClose: () -> Void

    var body: some View {
        @Bindable var viewModel = viewModel

        return ZStack {
            AppColor.mediaBackground.ignoresSafeArea()

            CameraViewfinderView(model: viewModel)

            countdownOverlay

            VStack {
                topBar
                Spacer()
                CameraZoomControlView(
                    options: viewModel.zoomOptions,
                    selected: viewModel.displayZoomFactor,
                    isFrontCamera: viewModel.isUsingFrontCamera,
                    onSelect: viewModel.setDisplayZoom,
                    onToggle: viewModel.toggleFrontZoom
                )
                bottomBar
            }
            .padding(Spacing.xl)
        }
        .sensoryFeedback(.impact, trigger: viewModel.isCapturing) { _, new in new }
        .sensoryFeedback(.impact, trigger: viewModel.countdown)
        .task {
            viewModel.cameraAppeared()
            viewModel.prepareLibraryAccess()
        }
        .onDisappear {
            viewModel.cameraDisappeared()
        }
        .sheet(isPresented: $viewModel.isGalleryPresented) {
            PhotoLibraryGridView(
                access: viewModel.libraryAccess,
                assets: viewModel.recentAssets,
                thumbnail: { await viewModel.thumbnail(forAsset: $0) },
                onPick: { viewModel.importAsset(id: $0) },
                onPickData: { viewModel.usePickedPhoto($0) }
            )
        }
    }

    // MARK: Layout

    private var topBar: some View {
        HStack {
            MediaCircleButtonView(systemName: "xmark", action: onClose)
                .accessibilityLabel(Text("common.close", bundle: .module))

            Spacer()

            MediaCircleButtonView(systemName: viewModel.isFlashOn ? "bolt.fill" : "bolt.slash") {
                viewModel.toggleFlash()
            }
            .accessibilityLabel(Text("capture.camera.flash", bundle: .module))

            Spacer()

            CaptureTimerButtonView(timer: viewModel.timer) {
                viewModel.cycleTimer()
            }
        }
    }

    @ViewBuilder
    private var countdownOverlay: some View {
        if let countdown = viewModel.countdown {
            Text(countdown, format: .number)
                .font(.system(size: 120, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.onMedia)
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: countdown)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var shutterCore: some View {
        if viewModel.countdown == nil {
            Circle().fill(AppColor.onMedia.opacity(0.35))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppColor.onMedia)
                .padding(Spacing.lg)
        }
    }

    private var bottomBar: some View {
        ZStack {
            Button {
                viewModel.capture()
            } label: {
                Circle()
                    .strokeBorder(AppColor.onMedia, lineWidth: 5)
                    .frame(width: 80, height: 80)
                    .overlay(shutterCore.padding(Spacing.sm))
            }
            .disabled(viewModel.isCapturing)
            .accessibilityLabel(
                viewModel.countdown == nil
                    ? Text("capture.camera.capture", bundle: .module)
                    : Text("capture.camera.cancelTimer", bundle: .module)
            )

            HStack {
                GalleryButtonView(thumbnail: viewModel.galleryThumbnail) {
                    viewModel.isGalleryPresented = true
                }
                Spacer()
                MediaCircleButtonView(systemName: "arrow.triangle.2.circlepath.camera") {
                    viewModel.flipCamera()
                }
                .accessibilityLabel(Text("capture.camera.flip", bundle: .module))
            }
        }
    }
}

private struct GalleryButtonView: View {
    let thumbnail: CGImage?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColor.onMedia)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(.rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(AppColor.onMedia.opacity(0.6), lineWidth: 1)
            }
        }
        .accessibilityLabel(Text("capture.camera.gallery", bundle: .module))
    }
}
