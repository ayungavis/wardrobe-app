import DesignSystem
import SwiftUI

/// Photo canvas with committed overlays; tapping an empty spot starts a new
/// text there. Dragging an overlay reveals a trash zone at the bottom.
struct EditorCanvasView: View {
    enum DraggedOverlay: Equatable {
        case text(UUID)
        case sticker(UUID)
    }

    let viewModel: EditorViewModel
    @Binding var canvasSize: CGSize
    @State private var dragging: DraggedOverlay?

    var body: some View {
        CanvasPhotoLayer(image: viewModel.croppedPreviewImage, canvasSize: $canvasSize)
            .gesture(tapToAddText)
            .overlay { committedOverlays }
            .overlay(alignment: .bottom) { trashZone }
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
                    onRotate: { viewModel.rotateSticker(id: item.id, to: $0) },
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
                        onRotate: { viewModel.rotateText(id: item.id, to: $0) },
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

/// The photo itself. Takes a plain value rather than the view model so moving
/// an overlay never invalidates (or re-decodes) the image layer.
private struct CanvasPhotoLayer: View {
    let image: CGImage?
    @Binding var canvasSize: CGSize

    var body: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .clipShape(.rect(cornerRadius: 12))
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { newSize in
                    canvasSize = newSize
                }
        } else {
            ProgressView()
                .tint(AppColor.onMedia)
        }
    }
}
