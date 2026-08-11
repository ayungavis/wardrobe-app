import DesignSystem
import SwiftUI

/// FR-015/016: story-style full-screen camera — dark, big shutter ring, lens
/// presets above it, gallery import on the left, flip on the right.
struct CameraStageView: View {
    let viewModel: CaptureFlowViewModel
    let onClose: () -> Void

    @State private var viewfinderSize: CGSize = .zero
    @State private var zoomStartValue: CGFloat?
    @State private var focusIndicator: FocusIndicator?

    /// A tap-to-focus square, identified so a new tap restarts the fade.
    private struct FocusIndicator: Equatable, Identifiable {
        let id = UUID()
        let point: CGPoint
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        return ZStack {
            AppColor.mediaBackground.ignoresSafeArea()

            viewfinder
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { newSize in
                    viewfinderSize = newSize
                }
                .gesture(focusTapGesture)
                .simultaneousGesture(zoomGesture)
                .overlay { focusSquare }

            VStack {
                topBar
                Spacer()
                CameraZoomControl(
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
                library: viewModel.library,
                onPick: { viewModel.importAsset(id: $0) },
                onPickData: { viewModel.usePickedPhoto($0) }
            )
        }
    }

    // MARK: Layout

    private var topBar: some View {
        HStack {
            MediaCircleButton(systemName: "xmark", action: onClose)
                .accessibilityLabel(Text("common.close", bundle: .module))

            Spacer()

            MediaCircleButton(systemName: viewModel.isFlashOn ? "bolt.fill" : "bolt.slash") {
                viewModel.toggleFlash()
            }
            .accessibilityLabel(Text("capture.camera.flash", bundle: .module))

            Spacer()

            // Balances the X so the flash button sits centered.
            Color.clear.frame(width: 44, height: 44)
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
                    .overlay(Circle().fill(AppColor.onMedia.opacity(0.35)).padding(8))
            }
            .disabled(viewModel.isCapturing)
            .accessibilityLabel(Text("capture.camera.capture", bundle: .module))

            HStack {
                GalleryButton(thumbnail: viewModel.galleryThumbnail) {
                    viewModel.isGalleryPresented = true
                }
                Spacer()
                MediaCircleButton(systemName: "arrow.triangle.2.circlepath.camera") {
                    viewModel.flipCamera()
                }
                .accessibilityLabel(Text("capture.camera.flip", bundle: .module))
            }
        }
    }

    @ViewBuilder
    private var viewfinder: some View {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Tap-to-focus square that fades out on its own.
    @ViewBuilder
    private var focusSquare: some View {
        if let focusIndicator, viewfinderSize != .zero {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(AppColor.onMedia, lineWidth: 1.5)
                .frame(width: 72, height: 72)
                .position(
                    x: focusIndicator.point.x * viewfinderSize.width,
                    y: focusIndicator.point.y * viewfinderSize.height
                )
                .allowsHitTesting(false)
                .task(id: focusIndicator.id) {
                    try? await Task.sleep(for: .seconds(1.2))
                    self.focusIndicator = nil
                }
        }
    }

    // MARK: Gestures & actions

    private var focusTapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                guard viewfinderSize != .zero else { return }
                let point = CGPoint(
                    x: min(1, max(0, value.location.x / viewfinderSize.width)),
                    y: min(1, max(0, value.location.y / viewfinderSize.height))
                )
                viewModel.focus(at: point)
                focusIndicator = FocusIndicator(point: point)
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = zoomStartValue ?? viewModel.displayZoomFactor
                zoomStartValue = start
                viewModel.setDisplayZoom(start * value.magnification)
            }
            .onEnded { _ in zoomStartValue = nil }
    }
}

/// Lens presets (0.5x/1x/2x) on the back camera; a single in/out toggle on the
/// front, matching the built-in Camera app.
private struct CameraZoomControl: View {
    let options: [CGFloat]
    let selected: CGFloat
    let isFrontCamera: Bool
    let onSelect: (CGFloat) -> Void
    let onToggle: () -> Void

    var body: some View {
        Group {
            if options.count < 2 {
                EmptyView()
            } else if isFrontCamera {
                frontToggle
            } else {
                presetRow
            }
        }
        .padding(.bottom, Spacing.lg)
    }

    private var presetRow: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(options, id: \.self) { option in
                Button {
                    onSelect(option)
                } label: {
                    Text(verbatim: Self.label(for: option))
                        .font(AppFont.caption.weight(.semibold))
                        .foregroundStyle(isSelected(option) ? AppColor.accent : AppColor.onMedia)
                        .frame(width: 44, height: 44)
                        .background(isSelected(option) ? AppColor.onMedia.opacity(0.25) : .clear, in: Circle())
                }
                .accessibilityLabel(Text(verbatim: Self.label(for: option)))
                .accessibilityAddTraits(isSelected(option) ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, Spacing.xs)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
    }

    private var frontToggle: some View {
        Button(action: onToggle) {
            Image(systemName: isZoomedIn ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColor.onMedia)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .environment(\.colorScheme, .dark)
        }
        .accessibilityLabel(Text(isZoomedIn ? "capture.camera.zoomOut" : "capture.camera.zoomIn", bundle: .module))
    }

    private var isZoomedIn: Bool {
        guard let last = options.last else { return false }
        return selected >= last
    }

    private func isSelected(_ option: CGFloat) -> Bool {
        abs(selected - option) < 0.05
    }

    private static func label(for option: CGFloat) -> String {
        option == option.rounded() ? "\(Int(option))x" : "\(option)x"
    }
}

/// IG-style gallery entry point: the newest photo as a thumbnail once the
/// library permission allows it, a plain icon otherwise.
private struct GalleryButton: View {
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
