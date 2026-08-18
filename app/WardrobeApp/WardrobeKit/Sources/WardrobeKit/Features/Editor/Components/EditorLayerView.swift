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
            .accessibilityAction(named: Text("editor.layer.select", bundle: .module), onSelect)
            .accessibilityAction(named: Text("editor.layer.delete", bundle: .module), onDelete)
            .accessibilityIdentifier("editor.layer")
    }

    /// Only the settle is animated. Live gesture updates arrive through
    /// `@GestureState`, which these `value:` triggers never see, so the layer
    /// still tracks the finger frame for frame.
    private var settleAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.2)
    }

    private var accessibilityLabel: Text {
        switch layer.content {
        case let .text(text):
            Text(verbatim: text.content)
        case .sticker:
            // The emoji itself is not speakable, so Voice Control could not
            // target it.
            Text("editor.layer.sticker", bundle: .module)
        case .photo:
            Text("editor.layer.photo", bundle: .module)
        case .drawing:
            Text("editor.layer.drawing", bundle: .module)
        }
    }

    /// §19: the guides and badges cannot be the only way to know a layer is
    /// aligned, so the same alignment they draw is also what VoiceOver reads —
    /// from one function, so the two can never say different things.
    private var accessibilityValue: Text {
        let percent = Int((layer.transform.scale * 100).rounded())
        let degrees = CanvasSnapping.readableDegrees(layer.transform.rotationDegrees)

        guard let alignment = alignmentPhrase else {
            return Text("editor.layer.transform \(percent) \(degrees)", bundle: .module)
        }
        return Text("editor.layer.transformAligned \(percent) \(degrees) \(alignment)", bundle: .module)
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
                    isOverDeleteTarget ? AppColor.destructive : AppColor.accent,
                    style: StrokeStyle(
                        lineWidth: inverseScale,
                        dash: [6 * inverseScale, 4 * inverseScale]
                    )
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
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
