import CoreGraphics
import DesignSystem
import SwiftUI

/// One layer on the canvas: its content, its selection chrome, and the drag /
/// pinch / rotate that move it (FR-085).
///
/// The layer owns the *live* transform and the view model only ever sees the
/// settled one, so a gesture that is interrupted leaves the document exactly as
/// it was — FR-085's restore rule holds because nothing was written, not
/// because something was undone.
struct EditorLayerView: View {
    let layer: EditorLayer
    let canvasSize: CGSize
    let photo: CGImage?
    let isSelected: Bool
    let isOverDeleteTarget: Bool
    let onSelect: () -> Void
    let onDoubleTap: () -> Void
    /// Reports the live snap so the canvas can light up the delete target and
    /// show the guides and badges.
    let onSnapChanged: (CanvasSnap) -> Void
    let onTransformEnded: (ElementTransform) -> Void
    let onDelete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var gesture = TransientTransform()
    @State private var contentSize: CGSize = .zero

    private var liveSnap: CanvasSnap {
        CanvasSnapping.snap(
            committed: layer.transform,
            translation: gesture.translation,
            magnification: gesture.magnification,
            rotationDelta: gesture.rotationDegrees,
            canvasSize: canvasSize
        )
    }

    var body: some View {
        let transform = liveSnap.transform

        LayerContentView(content: layer.content, canvasSize: canvasSize, photo: photo)
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newSize in
                contentSize = newSize
            }
            .contentShape(Rectangle())
            .overlay { selectionChrome(scale: transform.scale) }
            .scaleEffect(isOverDeleteTarget ? 0.82 : 1)
            .canvasLayerTransform(transform, in: canvasSize)
            .opacity(isOverDeleteTarget ? 0.48 : 1)
            .animation(settleAnimation, value: isOverDeleteTarget)
            .animation(settleAnimation, value: layer.transform)
            .onTapGesture(count: 2, perform: onDoubleTap)
            .onTapGesture(perform: onSelect)
            .gesture(transformGesture, including: layer.isLocked ? .subviews : .all)
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityActions {
                Button(action: onSelect) { Text("editor.layer.select", bundle: .module) }
                // Offering Delete on a locked layer would advertise an action
                // the document refuses (FR-087).
                if !layer.isLocked {
                    Button(action: onDelete) { Text("editor.layer.delete", bundle: .module) }
                }
            }
            .accessibilityIdentifier("editor.layer")
    }

    /// Only the settle is animated. Live gesture updates arrive through
    /// `@GestureState`, which these `value:` triggers never see, so the layer
    /// still tracks the finger frame for frame.
    private var settleAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.2)
    }

    /// Shared with the panel row, so a layer has one name wherever you meet it.
    /// A sticker is named by its kind rather than its glyph — an emoji is not
    /// speakable, so Voice Control could not target it.
    private var accessibilityLabel: Text {
        Text(verbatim: LayerLabel.title(for: layer.content))
    }

    /// Everything §19 asks a canvas layer to announce: position, scale,
    /// rotation, and — because the guides and badges cannot be the only way to
    /// know — alignment and lock state.
    ///
    /// Built as separate phrases rather than one format. Two optional tails on
    /// a single string would need a key per combination, and the alignment
    /// still comes from `CanvasSnapping.alignment`, so the line that gets drawn
    /// and the words that get spoken cannot disagree.
    private var accessibilityValue: Text {
        Text(verbatim: valuePhrases.joined(separator: ", "))
    }

    private var valuePhrases: [String] {
        let transform = layer.transform
        var phrases = [
            String(
                localized: "editor.layer.position \(percent(transform.position.x)) \(percent(transform.position.y))",
                bundle: .module
            ),
            String(localized: "editor.layer.scale \(percent(transform.scale))", bundle: .module),
            String(
                localized: "editor.layer.rotation \(CanvasSnapping.readableDegrees(transform.rotationDegrees))",
                bundle: .module
            ),
        ]
        if let alignmentPhrase {
            phrases.append(alignmentPhrase)
        }
        if layer.isLocked {
            phrases.append(LocalizedKey.resolve("editor.layer.locked"))
        }
        return phrases
    }

    private func percent(_ value: CGFloat) -> Int {
        Int((value * 100).rounded())
    }

    private var alignmentPhrase: String? {
        switch CanvasSnapping.alignment(of: layer.transform.position, in: canvasSize) {
        case .none: nil
        case .centredHorizontally: LocalizedKey.resolve("editor.layer.aligned.horizontally")
        case .centredVertically: LocalizedKey.resolve("editor.layer.aligned.vertically")
        case .centred: LocalizedKey.resolve("editor.layer.aligned.both")
        }
    }

    /// Every metric is divided by the scale so the outline stays one point wide
    /// on screen however far the layer is zoomed.
    @ViewBuilder
    private func selectionChrome(scale: CGFloat) -> some View {
        if isSelected {
            let inverseScale = 1 / max(scale, ElementTransform.scaleRange.lowerBound)
            RoundedRectangle(cornerRadius: 6 * inverseScale)
                .stroke(
                    outlineColor,
                    style: StrokeStyle(
                        lineWidth: inverseScale,
                        dash: [6 * inverseScale, 4 * inverseScale]
                    )
                )
                .overlay(alignment: .topTrailing) {
                    if layer.isLocked {
                        lockBadge(inverseScale: inverseScale)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Over the delete target wins: that is about to happen, while locked is a
    /// standing state.
    private var outlineColor: Color {
        if isOverDeleteTarget {
            return AppColor.destructive
        }
        return layer.isLocked ? AppColor.warning : AppColor.accent
    }

    /// Why a gesture is being ignored, said where the gesture is happening
    /// (FR-086). Scaled like the outline, so it stays the same size on screen
    /// however far the layer is zoomed.
    private func lockBadge(inverseScale: CGFloat) -> some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 11 * inverseScale, weight: .bold))
            .foregroundStyle(AppColor.onMedia)
            .frame(width: 24 * inverseScale, height: 24 * inverseScale)
            .background(AppColor.warning, in: Circle())
            .overlay {
                Circle().stroke(AppColor.onMedia.opacity(0.82), lineWidth: inverseScale)
            }
            .offset(x: 8 * inverseScale, y: -8 * inverseScale)
    }

    private var transformGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .simultaneously(with: MagnifyGesture().simultaneously(with: RotateGesture()))
            .updating($gesture) { value, state, _ in
                state.translation = value.first?.translation ?? .zero
                state.magnification = value.second?.first?.magnification ?? 1
                state.rotationDegrees = value.second?.second?.rotation.degrees ?? 0
            }
            .onChanged { value in
                onSnapChanged(proposedSnap(for: value))
            }
            .onEnded { value in
                onTransformEnded(settled(proposedSnap(for: value).transform))
            }
    }

    private typealias TransformValue = SimultaneousGesture<
        DragGesture, SimultaneousGesture<MagnifyGesture, RotateGesture>
    >.Value

    /// Read from the gesture value rather than from `@GestureState`, whose
    /// update is not ordered against these callbacks — but composed by the same
    /// function as the drawn one, so the two cannot drift apart.
    private func proposedSnap(for value: TransformValue) -> CanvasSnap {
        CanvasSnapping.snap(
            committed: layer.transform,
            translation: value.first?.translation ?? .zero,
            magnification: value.second?.first?.magnification ?? 1,
            rotationDelta: value.second?.second?.rotation.degrees ?? 0,
            canvasSize: canvasSize
        )
    }

    /// Boundary clamping happens here, once, at the end — during the drag the
    /// layer follows the finger anywhere and then settles back.
    private func settled(_ transform: ElementTransform) -> ElementTransform {
        var settled = transform
        settled.position = CanvasGeometry.constrainedPosition(
            transform.position,
            canvasSize: canvasSize,
            layerSize: contentSize,
            scale: transform.scale,
            rotationDegrees: transform.rotationDegrees
        )
        return settled
    }
}

/// Resets itself when the gesture ends, so a released layer never keeps a
/// stale offset — the same shape `CropView` uses.
private struct TransientTransform: Equatable {
    var translation: CGSize = .zero
    var magnification: CGFloat = 1
    var rotationDegrees: Double = 0
}
