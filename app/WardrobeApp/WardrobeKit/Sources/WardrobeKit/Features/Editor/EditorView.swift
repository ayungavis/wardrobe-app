import DesignSystem
import SwiftUI

/// Story-style editor: full-bleed photo on black, tool rail on the right,
/// send arrow bottom-right (Mobbin ref: Instagram "Creating a story").
public struct EditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: EditorViewModel
    @State private var canvasSize: CGSize = .zero

    public init(viewModel: EditorViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    public var body: some View {
        @Bindable var viewModel = viewModel

        ZStack {
            AppColor.mediaBackground.ignoresSafeArea()
            content
        }
        .environment(\.colorScheme, .dark)
        .task { viewModel.onAppear() }
        .sheet(isPresented: $viewModel.isExportPresented) {
            ExportSheetView(viewModel: viewModel)
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
    private var content: some View {
        switch viewModel.originalData {
        case .idle, .loading:
            ProgressView()
                .tint(AppColor.onMedia)
        case let .failed(error):
            LoadFailedView(error: error, onRetry: { viewModel.load() })
        case .loaded:
            if case let .crop(spec) = viewModel.activeTool {
                CropStageView(
                    image: viewModel.previewImage,
                    spec: spec,
                    onChange: { viewModel.updateWorking(crop: $0) },
                    onCancel: { viewModel.cancelTool() },
                    onDone: { viewModel.commitTool() }
                )
            } else {
                canvasStage
            }
        }
    }

    private var canvasStage: some View {
        ZStack {
            EditorCanvasView(
                viewModel: viewModel,
                canvasSize: $canvasSize
            )

            if viewModel.activeTool == nil {
                EditorControlsOverlay(
                    onClose: { dismiss() },
                    onText: { viewModel.beginNewText() },
                    onCrop: { viewModel.beginCrop() },
                    onSend: { viewModel.beginExport() }
                )
            }

            if case let .text(working, isNew) = viewModel.activeTool {
                TextComposerOverlay(
                    working: working,
                    isExisting: !isNew,
                    onContentChange: { newContent in
                        var updated = working
                        updated.content = newContent
                        viewModel.updateWorking(text: updated)
                    },
                    onDelete: { viewModel.removeWorkingText() },
                    onCancel: { viewModel.cancelTool() },
                    onDone: { viewModel.commitTool() }
                )
            }
        }
    }
}

/// Photo canvas with committed text overlays; tapping an empty spot starts a
/// new text there (story-style).
private struct EditorCanvasView: View {
    let viewModel: EditorViewModel
    @Binding var canvasSize: CGSize

    var body: some View {
        if let image = viewModel.croppedPreviewImage {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .clipShape(.rect(cornerRadius: 12))
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { newSize in
                    canvasSize = newSize
                }
                .gesture(tapToAddText)
                .overlay { committedTexts }
        } else {
            ProgressView()
                .tint(AppColor.onMedia)
        }
    }

    private var tapToAddText: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                guard canvasSize != .zero, viewModel.activeTool == nil else { return }
                viewModel.beginNewText(at: CGPoint(
                    x: min(1, max(0, value.location.x / canvasSize.width)),
                    y: min(1, max(0, value.location.y / canvasSize.height))
                ))
            }
    }

    private var committedTexts: some View {
        ZStack {
            ForEach(viewModel.draft.texts) { item in
                if !isEditing(item) {
                    CommittedTextView(
                        item: item,
                        canvasSize: canvasSize,
                        onTap: { viewModel.beginEditingText(item) },
                        onMove: { viewModel.moveText(id: item.id, to: $0) },
                        onScale: { viewModel.scaleText(id: item.id, to: $0) },
                        onManipulationEnd: { viewModel.finishDirectManipulation() }
                    )
                }
            }
        }
    }

    private func isEditing(_ item: TextItem) -> Bool {
        if case let .text(working, _) = viewModel.activeTool {
            return working.id == item.id
        }
        return false
    }
}

/// X top-left, tool rail top-right, send arrow bottom-right.
private struct EditorControlsOverlay: View {
    let onClose: () -> Void
    let onText: () -> Void
    let onCrop: () -> Void
    let onSend: () -> Void

    var body: some View {
        VStack {
            HStack(alignment: .top) {
                MediaCircleButton(systemName: "xmark", action: onClose)
                    .accessibilityLabel(Text("common.close", bundle: .module))

                Spacer()

                VStack(spacing: Spacing.md) {
                    MediaCircleButton(systemName: "textformat", action: onText)
                        .accessibilityLabel(Text("editor.addText", bundle: .module))
                    MediaCircleButton(systemName: "crop", action: onCrop)
                        .accessibilityLabel(Text("editor.tool.crop", bundle: .module))
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button(action: onSend) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(AppColor.onMedia)
                        .frame(width: 56, height: 56)
                        .background(AppColor.accent, in: Circle())
                }
                .accessibilityLabel(Text("editor.export.title", bundle: .module))
            }
        }
        .padding(Spacing.lg)
    }
}

/// Crop tool with its own Cancel/Done bar, dark styled.
private struct CropStageView: View {
    let image: CGImage?
    let spec: CropSpec
    let onChange: (CropSpec) -> Void
    let onCancel: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onCancel) {
                    Text("common.cancel", bundle: .module)
                        .frame(minHeight: 44)
                }

                Spacer()

                Button(action: onDone) {
                    Text("common.done", bundle: .module)
                        .bold()
                        .frame(minHeight: 44)
                }
            }
            .foregroundStyle(AppColor.onMedia)
            .padding(.horizontal, Spacing.lg)

            CropToolView(image: image, spec: spec, onChange: onChange)
                .padding(Spacing.lg)
        }
    }
}

private struct LoadFailedView: View {
    let error: AppError
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("common.errorTitle", bundle: .module)
            } icon: {
                Image(systemName: "photo.badge.exclamationmark")
            }
        } description: {
            Text(error.userMessage)
        } actions: {
            Button(action: onRetry) {
                Text("common.retry", bundle: .module)
            }
        }
    }
}

/// Pinch resizes and drag moves the crop window over the full image.
struct CropToolView: View {
    let image: CGImage?
    let spec: CropSpec
    let onChange: (CropSpec) -> Void

    @State private var viewSize: CGSize = .zero
    @State private var baseRect: CGRect?

    var body: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { newSize in
                    viewSize = newSize
                }
                .overlay {
                    CropWindowShape(rect: denormalized(spec.rect))
                        .fill(AppColor.mediaBackground.opacity(0.5), style: FillStyle(eoFill: true))
                    Rectangle()
                        .path(in: denormalized(spec.rect))
                        .stroke(AppColor.onMedia, lineWidth: 2)
                }
                .gesture(dragGesture.simultaneously(with: magnifyGesture))
        } else {
            ProgressView()
                .tint(AppColor.onMedia)
        }
    }

    private func denormalized(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x * viewSize.width,
            y: rect.origin.y * viewSize.height,
            width: rect.width * viewSize.width,
            height: rect.height * viewSize.height
        )
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard viewSize != .zero else { return }
                let base = baseRect ?? spec.rect
                baseRect = base
                var rect = base
                rect.origin.x += value.translation.width / viewSize.width
                rect.origin.y += value.translation.height / viewSize.height
                onChange(CropSpec(rect: rect.clampedToUnitSpace()))
            }
            .onEnded { _ in baseRect = nil }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = baseRect ?? spec.rect
                baseRect = base
                let width = min(1, max(0.2, base.width / value.magnification))
                let height = min(1, max(0.2, base.height / value.magnification))
                let rect = CGRect(
                    x: base.midX - width / 2,
                    y: base.midY - height / 2,
                    width: width,
                    height: height
                )
                onChange(CropSpec(rect: rect.clampedToUnitSpace()))
            }
            .onEnded { _ in baseRect = nil }
    }
}

/// Even-odd shape dimming everything outside the crop window.
private struct CropWindowShape: Shape {
    let rect: CGRect

    func path(in bounds: CGRect) -> Path {
        var path = Path()
        path.addRect(bounds)
        path.addRect(rect.intersection(bounds))
        return path
    }
}

private extension CGRect {
    /// Keeps the rect inside the unit square without changing its size.
    func clampedToUnitSpace() -> CGRect {
        var rect = self
        rect.origin.x = min(max(rect.origin.x, 0), 1 - width)
        rect.origin.y = min(max(rect.origin.y, 0), 1 - height)
        return rect
    }
}
