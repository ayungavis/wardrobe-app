import DesignSystem
import SwiftUI

public struct CropView: View {
    public enum Exit {
        case retake
        case cancel
    }

    @State private var viewModel: CropViewModel
    private let exit: Exit
    private let initialCrop: CropSpec?
    private let aspectRatio: CGFloat
    private let onExit: () -> Void
    private let onUseCrop: (CropSpec) -> Void

    public init(
        viewModel: CropViewModel,
        exit: Exit = .retake,
        initialCrop: CropSpec? = nil,
        aspectRatio: CGFloat,
        onExit: @escaping () -> Void,
        onUseCrop: @escaping (CropSpec) -> Void
    ) {
        _viewModel = State(wrappedValue: viewModel)
        self.exit = exit
        self.initialCrop = initialCrop
        self.aspectRatio = aspectRatio
        self.onExit = onExit
        self.onUseCrop = onUseCrop
    }

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var hasRestoredCrop = false
    @GestureState private var gesture = TransientGesture()

    private static let zoomStep: CGFloat = 0.5
    private static let canvasInsets = CGSize(width: 32, height: 220)

    public var body: some View {
        Group {
            switch viewModel.image {
            case .idle, .loading:
                ProgressView().tint(AppColor.onMedia)
            case let .failed(error):
                failed(error)
            case let .loaded(image):
                framing(image)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.mediaBackground.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .task { viewModel.load() }
    }

    private func framing(_ image: CGImage) -> some View {
        let imageSize = CGSize(width: image.width, height: image.height)

        return GeometryReader { proxy in
            let cropSize = CropGeometry.cropSize(
                fitting: proxy.size, insets: Self.canvasInsets, aspectRatio: aspectRatio
            )

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: Spacing.lg)
                canvas(image: image, imageSize: imageSize, cropSize: cropSize)
                hint
                Spacer(minLength: Spacing.xl)
                useCropButton(imageSize: imageSize, cropSize: cropSize)
            }
            .task(id: cropSize) {
                restoreCrop(imageSize: imageSize, cropSize: cropSize)
            }
        }
    }

    private func restoreCrop(imageSize: CGSize, cropSize: CGSize) {
        guard !hasRestoredCrop, let initialCrop, cropSize.width > 0 else { return }
        hasRestoredCrop = true

        let framing = CropGeometry.framing(
            for: initialCrop.rect, imageSize: imageSize, cropSize: cropSize
        )
        scale = framing.scale
        offset = framing.offset
    }

    private func failed(_ error: AppError) -> some View {
        ContentUnavailableView {
            Text("crop.failed.title", bundle: .module)
        } description: {
            Text(error.userMessage)
        } actions: {
            Button(action: onExit) {
                Text("crop.retake", bundle: .module)
            }
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            Button(action: onExit) {
                Label {
                    Text(exit == .retake ? "crop.retake" : "common.cancel", bundle: .module)
                } icon: {
                    Image(systemName: "chevron.left")
                }
                .frame(minHeight: 44)
            }
            .accessibilityIdentifier(exit == .retake ? "crop.retake" : "crop.cancel")

            Spacer()

            Text("crop.title", bundle: .module)
                .font(AppFont.body)

            Spacer()

            Button {
                withAnimation(.snappy) {
                    scale = 1
                    offset = .zero
                }
            } label: {
                Text("crop.reset", bundle: .module)
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("crop.reset")
        }
        .foregroundStyle(AppColor.onMedia)
        .padding(.horizontal, Spacing.lg)
    }

    private var hint: some View {
        HStack(spacing: Spacing.lg) {
            zoomButton(
                systemImage: "minus.magnifyingglass",
                by: -Self.zoomStep,
                label: "crop.zoomOut",
                identifier: "crop.zoomOut"
            )
            Text("crop.hint", bundle: .module)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.onMedia.opacity(0.7))
            zoomButton(
                systemImage: "plus.magnifyingglass",
                by: Self.zoomStep,
                label: "crop.zoomIn",
                identifier: "crop.zoomIn"
            )
        }
        .padding(.top, Spacing.lg)
    }

    private func zoomButton(
        systemImage: String,
        by delta: CGFloat,
        label: LocalizedStringKey,
        identifier: String
    ) -> some View {
        Button {
            withAnimation(.snappy) {
                scale = CropGeometry.clampedScale(scale + delta)
            }
        } label: {
            Image(systemName: systemImage)
                .frame(minWidth: 44, minHeight: 44)
        }
        .foregroundStyle(AppColor.onMedia)
        .accessibilityLabel(Text(label, bundle: .module))
        .accessibilityIdentifier(identifier)
    }

    private func useCropButton(imageSize: CGSize, cropSize: CGSize) -> some View {
        Button {
            onUseCrop(
                CropSpec(
                    rect: CropGeometry.normalizedRect(
                        scale: scale,
                        offset: offset,
                        imageSize: imageSize,
                        cropSize: cropSize
                    )
                )
            )
        } label: {
            Text("crop.use", bundle: .module)
                .font(AppFont.body)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppColor.onMedia)
        .foregroundStyle(AppColor.mediaBackground)
        .accessibilityIdentifier("crop.use")
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.lg)
    }

    // MARK: Canvas

    private func canvas(image: CGImage, imageSize: CGSize, cropSize: CGSize) -> some View {
        let liveScale = CropGeometry.clampedScale(scale * gesture.magnification)
        let liveOffset = CropGeometry.clampedOffset(
            CGSize(
                width: offset.width + gesture.translation.width,
                height: offset.height + gesture.translation.height
            ),
            scale: liveScale,
            imageSize: imageSize,
            cropSize: cropSize
        )
        let fill = CropGeometry.aspectFillSize(imageSize: imageSize, cropSize: cropSize)

        return ZStack {
            AppColor.surface

            Image(decorative: image, scale: 1)
                .resizable()
                .frame(width: fill.width, height: fill.height)
                .scaleEffect(liveScale)
                .offset(liveOffset)

            CropGridView()
                .opacity(gesture.isActive ? 0.75 : 0)
        }
        .frame(width: cropSize.width, height: cropSize.height)
        .clipped()
        .overlay(Rectangle().stroke(AppColor.onMedia, lineWidth: 1))
        .contentShape(.rect)
        .gesture(framingGesture(imageSize: imageSize, cropSize: cropSize))
        .accessibilityIdentifier("crop.canvas")
        .accessibilityLabel(Text("crop.canvas.label", bundle: .module))
    }

    private func framingGesture(imageSize: CGSize, cropSize: CGSize) -> some Gesture {
        MagnifyGesture()
            .simultaneously(with: DragGesture(minimumDistance: 0))
            .updating($gesture) { value, state, _ in
                state.magnification = value.first?.magnification ?? 1
                state.translation = value.second?.translation ?? .zero
            }
            .onEnded { value in
                let newScale = CropGeometry.clampedScale(scale * (value.first?.magnification ?? 1))
                let translation = value.second?.translation ?? .zero
                scale = newScale
                offset = CropGeometry.clampedOffset(
                    CGSize(
                        width: offset.width + translation.width,
                        height: offset.height + translation.height
                    ),
                    scale: newScale,
                    imageSize: imageSize,
                    cropSize: cropSize
                )
            }
    }
}

// MARK: - Supporting types

private struct TransientGesture: Equatable {
    var magnification: CGFloat = 1
    var translation: CGSize = .zero

    var isActive: Bool {
        magnification != 1 || translation != .zero
    }
}

private struct CropGridView: View {
    var body: some View {
        ZStack {
            line(width: 0.5, height: nil, isHorizontal: false)
            line(width: nil, height: 0.5, isHorizontal: true)
        }
    }

    @ViewBuilder
    private func line(width: CGFloat?, height: CGFloat?, isHorizontal: Bool) -> some View {
        let bar = Rectangle()
            .fill(AppColor.onMedia.opacity(0.7))
            .frame(width: width, height: height)

        if isHorizontal {
            VStack(spacing: 0) {
                Spacer(); bar; Spacer(); bar; Spacer()
            }
        } else {
            HStack(spacing: 0) {
                Spacer(); bar; Spacer(); bar; Spacer()
            }
        }
    }
}
