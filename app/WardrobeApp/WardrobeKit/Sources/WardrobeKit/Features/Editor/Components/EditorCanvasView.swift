import CoreGraphics
import DesignSystem
import SwiftUI
#if os(iOS)
    import UIKit
#endif

struct EditorCanvasView: View {
    let viewModel: EditorViewModel
    @Binding var canvasSize: CGSize
    @State private var heldLayerID: UUID?
    @State private var isOverDeleteTarget = false
    /// True while a finger is doing something other than tapping. What closes
    /// the doors a stray double tap would otherwise open mid-gesture.
    @State private var isGestureEngaged = false
    @State private var snap: CanvasSnap?
    @State private var layerSizes: [UUID: CGSize] = [:]
    @State private var gesture = TransientTransform()

    var body: some View {
        CanvasFrameView(
            background: viewModel.document.background,
            photo: viewModel.preview(forPhoto:),
            canvasSize: $canvasSize
        )
        // Registered before the single tap that starts a new text, the same
        // ordering `EditorLayerView` already relies on.
        .onTapGesture(count: 2) { beginBackgroundCrop() }
        .gesture(backgroundTap)
        .overlay { layers }
        .overlay { guides }
        .overlay(alignment: .top) { snapBadges }
        .overlay { drawingSurface }
        .overlay(alignment: .bottom) { deleteTarget }
        // Declared out here, not on the frame inside: a named space is found by
        // walking up from where it is used, and the gesture below is the
        // ancestor. Overlays do not change the base's size, so this rect is the
        // canvas rect either way.
        .coordinateSpace(.named(CanvasTransformGestureModifier.coordinateSpace))
        .modifier(CanvasTransformGestureModifier(
            hitTest: hitTest(at:),
            onEngagementChanged: engagementChanged,
            onChanged: transformChanged,
            onEnded: transformFinished,
            onCancelled: endTransform
        ))
    }

    /// Only a layer the canvas may actually act on: a locked one, or any one
    /// while a tool is open, swallows the touch without being grabbed (FR-086).
    private func hitTest(at point: CGPoint) -> UUID? {
        guard let id = CanvasHitTest.layerID(
            at: point,
            in: viewModel.document,
            canvasSize: canvasSize,
            layerSizes: layerSizes
        ) else {
            return nil
        }
        guard let layer = viewModel.document.layer(id: id),
              EditorGesture.canHold(layer, activeTool: viewModel.activeTool)
        else {
            return nil
        }
        return id
    }

    private func transformChanged(_ update: CanvasTransformGestureModifier.Update) {
        gesture = TransientTransform(
            translation: update.translation,
            magnification: update.magnification,
            rotationDegrees: update.rotationDegrees
        )
        guard let layer = viewModel.document.layer(id: update.layerID) else { return }
        snapChanged(layer.id, to: snapping(
            for: layer,
            translation: update.translation,
            magnification: update.magnification,
            rotationDegrees: update.rotationDegrees
        ))
    }

    private func transformFinished(_ update: CanvasTransformGestureModifier.Update) {
        defer { endTransform() }
        guard let layer = viewModel.document.layer(id: update.layerID) else { return }
        let proposed = snapping(
            for: layer,
            translation: update.translation,
            magnification: update.magnification,
            rotationDegrees: update.rotationDegrees
        ).transform
        transformEnded(layer.id, to: settled(proposed, layer: layer))
    }

    private func endTransform() {
        gesture = TransientTransform()
    }

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
                        onSizeChanged: { layerSizes[layer.id] = $0 },
                        onDelete: { viewModel.removeLayer(id: layer.id) }
                    )
                    .zIndex(Double(index))
                }
            }
        }
    }

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
        if let heldLayerID, viewModel.canRemove(layerID: heldLayerID) {
            DeleteDropTargetView(isActive: isOverDeleteTarget)
                .transition(.opacity)
        }
    }

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

    /// The one place `heldLayerID` is written. A hold that never becomes a
    /// transform sends no action at all — the recogniser simply fails — so
    /// clearing it from the transform's end would leave it dangling.
    private func engagementChanged(_ isEngaged: Bool, _ layerID: UUID?) {
        isGestureEngaged = isEngaged
        heldLayerID = isEngaged ? layerID : nil
    }

    private func beginBackgroundCrop() {
        guard !isGestureEngaged else { return }
        viewModel.beginCrop(.background)
    }

    /// Refused mid-gesture: a second finger tapping twice while the first holds
    /// a layer must not yank the user into the composer or the crop screen.
    private func beginEditing(_ layer: EditorLayer) {
        guard !isGestureEngaged else { return }
        if let draft = layer.textDraft {
            viewModel.beginEditingText(draft)
        } else if case .photo = layer.content {
            viewModel.beginCrop(.layer(layer.id))
        }
    }

    private func snapChanged(_ id: UUID, to snap: CanvasSnap) {
        select(id)

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

private struct CanvasFrameView: View {
    let background: CanvasBackground
    let photo: (String) -> CGImage?
    @Binding var canvasSize: CGSize

    var body: some View {
        Color.clear
            .aspectRatio(StoryCanvas.aspectRatio, contentMode: .fit)
            .background(CanvasBackgroundView(background: background, photo: photo))
            .clipShape(.rect(cornerRadius: 12))
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newSize in
                canvasSize = newSize
            }
    }
}

private struct TransientTransform: Equatable {
    var translation: CGSize = .zero
    var magnification: CGFloat = 1
    var rotationDegrees: Double = 0
}
