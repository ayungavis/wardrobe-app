import CoreGraphics
import DesignSystem
import SwiftUI
#if os(iOS)
    import UIKit
#endif

/// The 9:16 canvas: the photo behind, the document's layers over it, and a
/// delete target that appears while one is being dragged.
///
/// Everything transient — which layer is under the finger, whether it is over
/// the delete target — lives here rather than in the view model. It changes
/// many times a second and means nothing once the finger lifts, so keeping it
/// out of the document is what stops a gesture from writing sixty times.
struct EditorCanvasView: View {
    let viewModel: EditorViewModel
    @Binding var canvasSize: CGSize
    @State private var interactingLayerID: UUID?
    @State private var isOverDeleteTarget = false

    var body: some View {
        CanvasPhotoLayer(image: viewModel.croppedPreviewImage, canvasSize: $canvasSize)
            .gesture(backgroundTap)
            .overlay { layers }
            .overlay(alignment: .bottom) { deleteTarget }
    }

    /// An empty spot dismisses the selection if there is one, and otherwise
    /// starts a new text where it was tapped — so the existing shortcut
    /// survives without becoming a mode.
    private var backgroundTap: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                guard canvasSize != .zero, viewModel.activeTool == nil else { return }
                guard viewModel.selectedLayerID == nil else {
                    viewModel.select(nil)
                    return
                }
                viewModel.beginNewText(at: CGPoint(
                    x: min(1, max(0, value.location.x / canvasSize.width)),
                    y: min(1, max(0, value.location.y / canvasSize.height))
                ))
            }
    }

    private var layers: some View {
        ZStack {
            ForEach(Array(viewModel.document.layers.enumerated()), id: \.element.id) { index, layer in
                if isInteractive(layer) {
                    EditorLayerView(
                        layer: layer,
                        canvasSize: canvasSize,
                        isSelected: viewModel.selectedLayerID == layer.id,
                        isOverDeleteTarget: isOverDeleteTarget && interactingLayerID == layer.id,
                        onSelect: { select(layer.id) },
                        onDoubleTap: { beginEditing(layer) },
                        onDragChanged: { dragChanged(layer.id, to: $0) },
                        onTransformEnded: { transformEnded(layer.id, to: $0) },
                        onDelete: { viewModel.removeLayer(id: layer.id) }
                    )
                    // Array order is z-order; the index is the position, the
                    // UUID stays the identity.
                    .zIndex(Double(index))
                }
            }
        }
    }

    @ViewBuilder
    private var deleteTarget: some View {
        if interactingLayerID != nil {
            DeleteDropTargetView(isActive: isOverDeleteTarget)
                .transition(.opacity)
        }
    }

    /// The photo is the canvas background until it gets a polaroid frame, and
    /// the text open in the composer is drawn by the composer instead.
    private func isInteractive(_ layer: EditorLayer) -> Bool {
        if case .photo = layer.content {
            return false
        }
        if case let .text(working, _) = viewModel.activeTool, working.id == layer.id {
            return false
        }
        return true
    }

    // MARK: Interaction

    private func select(_ id: UUID) {
        guard viewModel.selectedLayerID != id else { return }
        viewModel.select(id)
        CanvasHaptics.selectionChanged()
    }

    private func beginEditing(_ layer: EditorLayer) {
        guard let item = layer.textItem else { return }
        viewModel.beginEditingText(item)
    }

    private func dragChanged(_ id: UUID, to position: CGPoint) {
        interactingLayerID = id
        select(id)

        let isOver = CanvasGeometry.isOverDeleteTarget(position)
        guard isOver != isOverDeleteTarget else { return }
        isOverDeleteTarget = isOver
        if isOver {
            CanvasHaptics.enteredDeleteTarget()
        }
    }

    private func transformEnded(_ id: UUID, to transform: ElementTransform) {
        let shouldDelete = isOverDeleteTarget && interactingLayerID == id
        interactingLayerID = nil
        isOverDeleteTarget = false

        if shouldDelete {
            CanvasHaptics.deleted()
            viewModel.removeLayer(id: id)
        } else {
            viewModel.commitTransform(layerID: id, to: transform)
        }
    }
}

/// The story frame: a 9:16 window with the photo aspect-filled into it, the
/// same framing the camera preview showed and the same one the export uses.
///
/// Takes a plain value rather than the view model so moving a layer never
/// invalidates (or re-decodes) the image layer.
private struct CanvasPhotoLayer: View {
    let image: CGImage?
    @Binding var canvasSize: CGSize

    var body: some View {
        Color.clear
            .aspectRatio(StoryCanvas.aspectRatio, contentMode: .fit)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                } else {
                    ProgressView()
                        .tint(AppColor.onMedia)
                }
            }
            .clipShape(.rect(cornerRadius: 12))
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newSize in
                canvasSize = newSize
            }
    }
}

// ponytail: called straight through, no protocol and no injection — three
// lines do not earn a service. Lift it into one the moment a view model needs
// to trigger feedback or a test needs to assert it.
private enum CanvasHaptics {
    static func selectionChanged() {
        #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    static func enteredDeleteTarget() {
        #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    static func deleted() {
        #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}
