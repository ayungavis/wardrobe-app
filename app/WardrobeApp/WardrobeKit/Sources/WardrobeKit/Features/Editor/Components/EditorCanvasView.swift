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
    /// What the current gesture last landed on. Transient like the two above —
    /// it means nothing once the finger lifts.
    @State private var snap: CanvasSnap?

    var body: some View {
        CanvasFrameView(background: viewModel.document.background, canvasSize: $canvasSize)
            .gesture(backgroundTap)
            .overlay { layers }
            .overlay { guides }
            .overlay(alignment: .top) { snapBadges }
            .overlay { drawingSurface }
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
                        photo: viewModel.croppedPreviewImage,
                        isSelected: viewModel.selectedLayerID == layer.id,
                        isOverDeleteTarget: isOverDeleteTarget && interactingLayerID == layer.id,
                        onSelect: { select(layer.id) },
                        onDoubleTap: { beginEditing(layer) },
                        onSnapChanged: { snapChanged(layer.id, to: $0) },
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

    /// Suppressed over the delete target: a layer about to be thrown away has
    /// nothing to align to.
    @ViewBuilder
    private var guides: some View {
        if let snap, !isOverDeleteTarget {
            CanvasGuidesView(alignment: snap.alignment)
        }
    }

    @ViewBuilder
    private var snapBadges: some View {
        if let snap, !isOverDeleteTarget {
            VStack(spacing: Spacing.sm) {
                if let degrees = snap.snappedRotationDegrees {
                    SnapBadgeView(
                        systemName: "arrow.clockwise",
                        value: Text(
                            "editor.snap.degrees \(CanvasSnapping.readableDegrees(degrees))",
                            bundle: .module
                        )
                    )
                }
                if let scale = snap.snappedScale {
                    SnapBadgeView(
                        systemName: "arrow.up.left.and.arrow.down.right",
                        value: Text(
                            "editor.snap.scale \(Int((scale * 100).rounded()))",
                            bundle: .module
                        )
                    )
                }
            }
            .padding(.top, Spacing.xxl)
        }
    }

    /// Mounted above the layers on purpose: it takes the touch first, so a
    /// stroke drawn across a sticker draws instead of dragging the sticker.
    @ViewBuilder
    private var drawingSurface: some View {
        if case let .drawing(session) = viewModel.activeTool {
            DrawingSurfaceView(session: session, pen: viewModel.pen) { points in
                viewModel.finishStroke(points, canvasSize: canvasSize)
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

    /// Only the text open in the composer is skipped — the composer draws it
    /// instead. The photo is a layer like any other now that it has a frame to
    /// sit in (FR-092).
    private func isInteractive(_ layer: EditorLayer) -> Bool {
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

    /// Double-tap reopens whatever the layer is made of: text goes back to the
    /// composer, the photo back to the crop screen. FR-019 says crop is not a
    /// tool in the rail — this is where it lives instead.
    private func beginEditing(_ layer: EditorLayer) {
        if let draft = layer.textDraft {
            viewModel.beginEditingText(draft)
        } else if case .photo = layer.content {
            viewModel.beginCrop()
        }
    }

    private func snapChanged(_ id: UUID, to snap: CanvasSnap) {
        interactingLayerID = id
        select(id)

        // Edge-triggered: feedback belongs to the moment something latches on,
        // not to every frame it stays there.
        let landedOnSomething = (snap.alignment != .none && self.snap?.alignment == CanvasAlignment.none)
            || (snap.snappedRotationDegrees != nil
                && snap.snappedRotationDegrees != self.snap?.snappedRotationDegrees)
            || (snap.snappedScale != nil && snap.snappedScale != self.snap?.snappedScale)
        self.snap = snap
        if landedOnSomething {
            CanvasHaptics.selectionChanged()
        }

        let isOver = CanvasGeometry.isOverDeleteTarget(snap.transform.position)
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
        snap = nil

        if shouldDelete {
            CanvasHaptics.deleted()
            viewModel.removeLayer(id: id)
        } else {
            viewModel.commitTransform(layerID: id, to: transform)
        }
    }
}

/// The 9:16 window the document is arranged inside, and the only thing that
/// measures it.
///
/// The rounded corner is editor chrome — the exported picture is square-edged,
/// because the corner belongs to the screen, not to the photograph.
private struct CanvasFrameView: View {
    let background: CanvasBackground
    @Binding var canvasSize: CGSize

    var body: some View {
        Color.clear
            .aspectRatio(StoryCanvas.aspectRatio, contentMode: .fit)
            .background(CanvasBackgroundView(background: background))
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
