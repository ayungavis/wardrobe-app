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
    /// The layer a finger is currently down on. The canvas owns the transform
    /// gesture, so this is what says which layer it acts on — and it is why a
    /// pinch works with only one finger on a tiny sticker.
    @State private var heldLayerID: UUID?
    @State private var isOverDeleteTarget = false
    /// What the current gesture last landed on. Transient like the rest — it
    /// means nothing once the finger lifts.
    @State private var snap: CanvasSnap?
    /// Each layer's drawn size, reported up, because clamping the settled
    /// position to the frame needs it and only the layer knows it.
    @State private var layerSizes: [UUID: CGSize] = [:]
    /// Plain `@State`: the recogniser reports its own end, so this is cleared
    /// there rather than by SwiftUI unwinding a gesture it no longer owns.
    @State private var gesture = TransientTransform()

    var body: some View {
        CanvasFrameView(background: viewModel.document.background, canvasSize: $canvasSize)
            .gesture(backgroundTap)
            .overlay { layers }
            .overlay { guides }
            .overlay(alignment: .top) { snapBadges }
            .overlay { drawingSurface }
            .overlay(alignment: .bottom) { deleteTarget }
            // Outside every overlay on purpose. `backgroundTap` above is
            // attached before them so it only sees the bare background; this
            // one has to be recognised *over* the layers, and over empty space
            // too, because the second finger of a pinch lands wherever it likes.
            .modifier(CanvasTransformGestureModifier(
                onChanged: { transformChanged($0, $1, $2) },
                onEnded: { transformFinished($0, $1, $2) },
                onCancelled: { gesture = TransientTransform() }
            ))
    }

    private func transformChanged(
        _ translation: CGSize, _ magnification: CGFloat, _ rotationDegrees: Double
    ) {
        gesture = TransientTransform(
            translation: translation, magnification: magnification, rotationDegrees: rotationDegrees
        )
        guard let layer = heldLayer else { return }
        snapChanged(layer.id, to: snapping(
            for: layer,
            translation: translation, magnification: magnification, rotationDegrees: rotationDegrees
        ))
    }

    private func transformFinished(
        _ translation: CGSize, _ magnification: CGFloat, _ rotationDegrees: Double
    ) {
        defer { gesture = TransientTransform() }
        guard let layer = heldLayer else { return }
        let proposed = snapping(
            for: layer,
            translation: translation, magnification: magnification, rotationDegrees: rotationDegrees
        ).transform
        transformEnded(layer.id, to: settled(proposed, layer: layer))
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
                        transform: liveTransform(for: layer),
                        photo: viewModel.preview(forPhoto:),
                        isSelected: viewModel.selectedLayerID == layer.id,
                        isOverDeleteTarget: isOverDeleteTarget && heldLayerID == layer.id,
                        isChallengePhoto: viewModel.challengePhotoLayerID == layer.id,
                        onSelect: { select(layer.id) },
                        onDoubleTap: { beginEditing(layer) },
                        onPressChanged: { pressChanged(layer, isPressed: $0) },
                        onSizeChanged: { layerSizes[layer.id] = $0 },
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
        // Never shown for a layer it could not take: dragging into a bin that
        // then does nothing is worse than no bin at all.
        if let heldLayerID, viewModel.canRemove(layerID: heldLayerID) {
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
        guard EditorGesture.canSelect(id, whileHolding: heldLayerID) else { return }
        guard viewModel.selectedLayerID != id else { return }
        viewModel.select(id)
        EditorHaptics.selection.play()
    }

    /// Double-tap reopens whatever the layer is made of: text goes back to the
    /// composer, the photo back to the crop screen. FR-019 says crop is not a
    /// tool in the rail — this is where it lives instead.
    private func beginEditing(_ layer: EditorLayer) {
        if let draft = layer.textDraft {
            viewModel.beginEditingText(draft)
        } else if case .photo = layer.content {
            viewModel.beginCrop(layerID: layer.id)
        }
    }

    private func snapChanged(_ id: UUID, to snap: CanvasSnap) {
        select(id)

        // Edge-triggered: feedback belongs to the moment something latches on,
        // not to every frame it stays there.
        let landedOnSomething = (snap.alignment != .none && self.snap?.alignment == CanvasAlignment.none)
            || (snap.snappedRotationDegrees != nil
                && snap.snappedRotationDegrees != self.snap?.snappedRotationDegrees)
            || (snap.snappedScale != nil && snap.snappedScale != self.snap?.snappedScale)
        self.snap = snap
        if landedOnSomething {
            EditorHaptics.latch.play()
        }

        guard viewModel.canRemove(layerID: id) else { return }

        let isOver = CanvasGeometry.isOverDeleteTarget(snap.transform.position)
        guard isOver != isOverDeleteTarget else { return }
        isOverDeleteTarget = isOver
        if isOver {
            EditorHaptics.armed.play()
        }
    }

    /// A press latches the layer the gesture will act on; lifting clears it.
    /// Refused for a locked layer and while a tool is open, so the pinch falls
    /// through to nothing rather than being silently ignored later.
    private func pressChanged(_ layer: EditorLayer, isPressed: Bool) {
        guard isPressed else {
            if heldLayerID == layer.id {
                heldLayerID = nil
            }
            return
        }
        heldLayerID = EditorGesture.hold(
            current: heldLayerID, pressing: layer, activeTool: viewModel.activeTool
        )
    }

    /// What a layer should draw right now: its committed transform, unless it
    /// is the one being held, in which case the live gesture is folded in.
    private func liveTransform(for layer: EditorLayer) -> ElementTransform {
        guard layer.id == heldLayerID else { return layer.transform }
        return snapping(
            for: layer,
            translation: gesture.translation,
            magnification: gesture.magnification,
            rotationDegrees: gesture.rotationDegrees
        ).transform
    }

    private func snapping(
        for layer: EditorLayer,
        translation: CGSize,
        magnification: CGFloat,
        rotationDegrees: Double
    ) -> CanvasSnap {
        CanvasSnapping.snap(
            committed: layer.transform,
            translation: translation,
            magnification: magnification,
            rotationDelta: rotationDegrees,
            canvasSize: canvasSize
        )
    }

    private var heldLayer: EditorLayer? {
        heldLayerID.flatMap { id in viewModel.document.layers.first { $0.id == id } }
    }

    /// Boundary clamping happens here, once, at the end — during the drag the
    /// layer follows the finger anywhere and then settles back.
    private func settled(_ transform: ElementTransform, layer: EditorLayer) -> ElementTransform {
        var settled = transform
        settled.position = CanvasGeometry.constrainedPosition(
            transform.position,
            canvasSize: canvasSize,
            layerSize: layerSizes[layer.id] ?? .zero,
            scale: transform.scale,
            rotationDegrees: transform.rotationDegrees
        )
        return settled
    }

    private func transformEnded(_ id: UUID, to transform: ElementTransform) {
        let shouldDelete = isOverDeleteTarget && heldLayerID == id
        isOverDeleteTarget = false
        snap = nil

        if shouldDelete {
            EditorHaptics.removed.play()
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

/// Resets itself when the gesture ends, so a released layer never keeps a
/// stale offset — the same shape `CropView` uses.
private struct TransientTransform: Equatable {
    var translation: CGSize = .zero
    var magnification: CGFloat = 1
    var rotationDegrees: Double = 0
}
