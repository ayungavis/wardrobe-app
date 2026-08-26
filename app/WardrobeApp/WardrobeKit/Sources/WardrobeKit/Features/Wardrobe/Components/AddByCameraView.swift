import DesignSystem
import SwiftUI

struct AddByCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var viewModel: AddByCameraViewModel

    init(viewModel: AddByCameraViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            Group {
                switch viewModel.phase {
                case .capturing: capturePhase
                case .reviewing: reviewPhase
                }
            }
            .toolbar { toolbar }
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
            .task { await viewModel.onAppear() }
            .onDisappear { viewModel.onDisappear() }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    viewModel.sceneBecameActive()
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            switch viewModel.phase {
            case .capturing:
                Button {
                    Task { await viewModel.beginReview() }
                } label: {
                    Text("wardrobe.scan.review", bundle: .module)
                }
                .disabled(viewModel.capturedCount == 0 || viewModel.isCapturing)
            case .reviewing:
                Button {
                    viewModel.confirm()
                    dismiss()
                } label: {
                    Text("wardrobe.review.confirm", bundle: .module)
                }
                .disabled(viewModel.review.garments.isEmpty)
            }
        }
        ToolbarItem(placement: .cancellationAction) {
            Button(role: .cancel) {
                viewModel.cancel()
                dismiss()
            } label: {
                Text("common.cancel", bundle: .module)
            }
        }
    }

    private var capturePhase: some View {
        ZStack {
            AppColor.mediaBackground.ignoresSafeArea()

            switch viewModel.permission {
            case .granted:
                cameraContent
            case .notDetermined:
                ProgressView()
            case .denied, .restricted:
                deniedState
            }
        }
    }

    @ViewBuilder
    private var reviewPhase: some View {
        if viewModel.review.isScanning {
            ProgressView {
                Text("wardrobe.scan.processing", bundle: .module)
            }
        } else if viewModel.review.activeGarments.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    retakeButton

                    GarmentDiscardHeaderView(
                        titleKey: "wardrobe.add.camera.empty.title",
                        messageKey: "wardrobe.add.camera.empty.message"
                    )
                    .padding(.top, Spacing.xxl)
                }
            }
            .padding(Spacing.lg)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    GarmentDiscardHeaderView(
                        titleKey: "wardrobe.review.title",
                        messageKey: "wardrobe.add.photos.review.message"
                    )
                    GarmentDiscardGridView(review: viewModel.review)
                }
                .padding(Spacing.lg)
            }
        }
    }

    private var retakeButton: some View {
        Button {
            viewModel.resumeCapturing()
        } label: {
            Image(systemName: "camera.fill")
                .font(AppFont.title.weight(.bold))
                .foregroundStyle(AppColor.onMedia)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Capsule().fill(AppColor.accent))
        }
    }

    private var cameraContent: some View {
        ZStack {
            CameraViewfinderView(model: viewModel)

            VStack {
                cameraTopBar
                Spacer()
                CameraZoomControlView(
                    options: viewModel.zoomOptions,
                    selected: viewModel.displayZoomFactor,
                    isFrontCamera: viewModel.isUsingFrontCamera,
                    onSelect: viewModel.setDisplayZoom,
                    onToggle: viewModel.toggleFrontZoom
                )
                captureBar
            }
            .padding(Spacing.xl)
        }
        .sensoryFeedback(.impact, trigger: viewModel.isCapturing) { _, new in new }
    }

    private var cameraTopBar: some View {
        HStack {
            Spacer()
            MediaCircleButtonView(systemName: viewModel.isFlashOn ? "bolt.fill" : "bolt.slash") {
                viewModel.toggleFlash()
            }
            .accessibilityLabel(Text("capture.camera.flash", bundle: .module))
            Spacer()
        }
    }

    private var captureBar: some View {
        ZStack {
            Button {
                viewModel.capture()
            } label: {
                Circle()
                    .strokeBorder(AppColor.onMedia, lineWidth: 5)
                    .frame(width: 80, height: 80)
                    .overlay(Circle().fill(AppColor.onMedia.opacity(0.35)).padding(Spacing.sm))
            }
            .disabled(viewModel.isCapturing)
            .accessibilityLabel(Text("capture.camera.capture", bundle: .module))

            HStack {
                CapturedStackView(
                    thumbnails: viewModel.capturedThumbnails,
                    count: viewModel.capturedCount
                ) {
                    Task { await viewModel.beginReview() }
                }

                Spacer()

                MediaCircleButtonView(systemName: "arrow.triangle.2.circlepath.camera") {
                    viewModel.flipCamera()
                }
                .accessibilityLabel(Text("capture.camera.flip", bundle: .module))
            }
        }
    }

    private var deniedState: some View {
        ContentUnavailableView {
            Label { Text("camera.permission.denied.title", bundle: .module) } icon: { Image(systemName: "camera") }
        } description: {
            Text("camera.permission.denied.wardrobe", bundle: .module)
        }
    }
}
