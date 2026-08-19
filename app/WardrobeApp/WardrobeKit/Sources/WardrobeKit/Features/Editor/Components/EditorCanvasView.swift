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
    @State private var snap: CanvasSnap?
    @State private var layerSizes: [UUID: CGSize] = [:]
    @State private var gesture = TransientTransform()

    var body: some View {
        CanvasFrameView(background: viewModel.document.background, canvasSize: $canvasSize)
            .gesture(backgroundTap)
            .overlay { layers }
            .overlay { guides }
            .overlay(alignment: .top) { snapBadges }
            .overlay { drawingSurface }
            .overlay(alignment: .bottom) { deleteTarget }
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

    private func beginEditing(_ layer: EditorLayer) {
        if let draft = layer.textDraft {
            viewModel.beginEditingText(draft)
        } else if case .photo = layer.content {
            viewModel.beginCrop(layerID: layer.id)
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

private struct TransientTransform: Equatable {
    var translation: CGSize = .zero
    var magnification: CGFloat = 1
    var rotationDegrees: Double = 0
}
