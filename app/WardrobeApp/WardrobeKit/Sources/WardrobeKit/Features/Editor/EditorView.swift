import DesignSystem
import SwiftUI

/// Story-style editor: full-bleed photo on black, tool rail on the right,
/// send arrow bottom-right (Mobbin ref: Instagram "Creating a story").
public struct EditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: EditorViewModel
    @State private var canvasSize: CGSize = .zero
    @State private var isDiscardConfirmPresented = false

    private let onDiscard: () -> Void

    public init(viewModel: EditorViewModel, onDiscard: @escaping () -> Void) {
        _viewModel = State(wrappedValue: viewModel)
        self.onDiscard = onDiscard
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
        .sheet(isPresented: $viewModel.isStickerPickerPresented) {
            StickerPickerSheet { viewModel.addSticker($0) }
        }
        .confirmationDialog(
            Text("editor.discard.title", bundle: .module),
            isPresented: $isDiscardConfirmPresented,
            titleVisibility: .visible
        ) {
            Button(role: .destructive, action: onDiscard) {
                Text("editor.discard.action", bundle: .module)
            }
            Button {
                dismiss() // FR-017: the draft survives; resume comes back here
            } label: {
                Text("editor.discard.keep", bundle: .module)
            }
            Button(role: .cancel) {} label: {
                Text("common.cancel", bundle: .module)
            }
        } message: {
            Text("editor.discard.message", bundle: .module)
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
                    isSaving: viewModel.isSaving,
                    didSave: viewModel.didSaveToPhotos,
                    onClose: { isDiscardConfirmPresented = true },
                    onText: { viewModel.beginNewText() },
                    onSticker: { viewModel.isStickerPickerPresented = true },
                    onCrop: { viewModel.beginCrop() },
                    onSave: { viewModel.saveDirectly() },
                    onSend: { viewModel.beginExport() }
                )
            }

            if case let .text(working, isNew) = viewModel.activeTool {
                TextComposerOverlay(
                    working: working,
                    isExisting: !isNew,
                    onUpdate: { viewModel.updateWorking(text: $0) },
                    onDelete: { viewModel.removeWorkingText() },
                    onCancel: { viewModel.cancelTool() },
                    onDone: { viewModel.commitTool() }
                )
            }
        }
    }
}

/// Photo canvas with committed overlays; tapping an empty spot starts a new
/// text there. Dragging an overlay reveals a trash zone at the bottom.
private struct EditorCanvasView: View {
    enum DraggedOverlay: Equatable {
        case text(UUID)
        case sticker(UUID)
    }

    let viewModel: EditorViewModel
    @Binding var canvasSize: CGSize
    @State private var dragging: DraggedOverlay?

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
                .overlay { committedOverlays }
                .overlay(alignment: .bottom) { trashZone }
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

    private var committedOverlays: some View {
        ZStack {
            ForEach(viewModel.draft.stickers) { item in
                CommittedStickerView(
                    item: item,
                    canvasSize: canvasSize,
                    onMove: { viewModel.moveSticker(id: item.id, to: $0) },
                    onScale: { viewModel.scaleSticker(id: item.id, to: $0) },
                    onDragActive: { active in
                        dragging = active ? .sticker(item.id) : nil
                        if !active {
                            finishDrag(.sticker(item.id))
                        }
                    },
                    onManipulationEnd: { viewModel.finishDirectManipulation() }
                )
            }

            ForEach(viewModel.draft.texts) { item in
                if !isEditing(item) {
                    CommittedTextView(
                        item: item,
                        canvasSize: canvasSize,
                        onTap: { viewModel.beginEditingText(item) },
                        onMove: { viewModel.moveText(id: item.id, to: $0) },
                        onScale: { viewModel.scaleText(id: item.id, to: $0) },
                        onDragActive: { active in
                            dragging = active ? .text(item.id) : nil
                            if !active {
                                finishDrag(.text(item.id))
                            }
                        },
                        onManipulationEnd: { viewModel.finishDirectManipulation() }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var trashZone: some View {
        if dragging != nil {
            Image(systemName: "trash")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppColor.onMedia)
                .frame(width: 56, height: 56)
                .background(.ultraThinMaterial, in: Circle())
                .padding(.bottom, Spacing.lg)
                .transition(.opacity)
        }
    }

    /// Dropping an overlay on the bottom-center trash zone deletes it.
    private func finishDrag(_ overlay: DraggedOverlay) {
        switch overlay {
        case let .text(id):
            let position = viewModel.draft.texts.first { $0.id == id }?.position
            if let position, isInTrashZone(position) {
                viewModel.removeText(id: id)
            }
        case let .sticker(id):
            let position = viewModel.draft.stickers.first { $0.id == id }?.position
            if let position, isInTrashZone(position) {
                viewModel.removeSticker(id: id)
            }
        }
    }

    private func isInTrashZone(_ position: CGPoint) -> Bool {
        abs(position.x - 0.5) < 0.15 && position.y > 0.85
    }

    private func isEditing(_ item: TextItem) -> Bool {
        if case let .text(working, _) = viewModel.activeTool {
            return working.id == item.id
        }
        return false
    }
}

/// X top-left, tool rail top-right, Save pill + send arrow at the bottom.
private struct EditorControlsOverlay: View {
    let isSaving: Bool
    let didSave: Bool
    let onClose: () -> Void
    let onText: () -> Void
    let onSticker: () -> Void
    let onCrop: () -> Void
    let onSave: () -> Void
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
                    MediaCircleButton(systemName: "face.smiling", action: onSticker)
                        .accessibilityLabel(Text("editor.tool.sticker", bundle: .module))
                    MediaCircleButton(systemName: "crop", action: onCrop)
                        .accessibilityLabel(Text("editor.tool.crop", bundle: .module))
                }
            }

            Spacer()

            HStack {
                savePill
                Spacer()
                sendButton
            }
        }
        .padding(Spacing.lg)
    }

    private var savePill: some View {
        Button(action: onSave) {
            HStack(spacing: Spacing.sm) {
                if isSaving {
                    ProgressView()
                        .tint(AppColor.onMedia)
                } else {
                    Image(systemName: didSave ? "checkmark" : "arrow.down.to.line")
                }
                Text(didSave ? "editor.saved" : "editor.save", bundle: .module)
            }
            .font(AppFont.body.weight(.semibold))
            .foregroundStyle(AppColor.onMedia)
            .padding(.horizontal, Spacing.lg)
            .frame(minHeight: 44)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .disabled(isSaving || didSave)
        .accessibilityLabel(Text("editor.save", bundle: .module))
    }

    private var sendButton: some View {
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
