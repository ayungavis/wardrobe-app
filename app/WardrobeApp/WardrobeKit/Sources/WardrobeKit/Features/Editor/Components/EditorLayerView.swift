import CoreGraphics
import DesignSystem
import SwiftUI

/// One layer on the canvas: its content, its selection chrome, and the press
/// that makes it the one a canvas gesture acts on.
///
/// It draws the *live* transform but does not compose it. The canvas owns the
/// drag, pinch, and rotate now, because a pinch has to be recognised wherever
/// the second finger lands — a sticker shrunk to thumbnail size cannot hold two
/// fingers. What stays here is the part that must be bounded by the layer's own
/// shape: knowing that a finger is on *this* layer.
struct EditorLayerView: View {
    let layer: EditorLayer
    let canvasSize: CGSize
    /// Composed by the canvas from the committed transform plus whatever the
    /// live gesture is doing, so an interrupted gesture leaves the document
    /// exactly as it was — FR-085's restore rule holds because nothing was
    /// written, not because something was undone.
    let transform: ElementTransform
    /// A lookup rather than one image: a document can hold more than one photo
    /// layer (FR-093), and handing the same pixels to every layer drew the same
    /// picture twice.
    let photo: (String) -> CGImage?
    let isSelected: Bool
    let isOverDeleteTarget: Bool
    let isChallengePhoto: Bool
    let onSelect: () -> Void
    let onDoubleTap: () -> Void
    /// Touch down and touch up on this layer. The canvas keeps the id so a
    /// pinch anywhere knows what it is acting on.
    let onPressChanged: (Bool) -> Void
    /// The canvas clamps the settled position to the frame, and needs the
    /// layer's drawn size to do it.
    let onSizeChanged: (CGSize) -> Void
    let onDelete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isPressed = false

    var body: some View {
        LayerContentView(content: layer.content, canvasSize: canvasSize, photo: photo)
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newSize in
                onSizeChanged(newSize)
            }
            .contentShape(LayerHitShape(content: layer.content, referenceWidth: canvasSize.width))
            .overlay { selectionChrome(scale: transform.scale) }
            .scaleEffect(isOverDeleteTarget ? 0.82 : 1)
            .canvasLayerTransform(transform, in: canvasSize)
            .opacity(isOverDeleteTarget ? 0.48 : 1)
            .animation(settleAnimation, value: isOverDeleteTarget)
            .animation(settleAnimation, value: layer.transform)
            .onTapGesture(count: 2, perform: onDoubleTap)
            .onTapGesture(perform: onSelect)
            // Zero distance so a finger that never moves still latches the
            // layer — that is the whole point, since the other finger is the
            // one doing the pinching. Simultaneous so it does not swallow the
            // two taps above.
            .simultaneousGesture(
                DragGesture(minimumDistance: 0).updating($isPressed) { _, state, _ in state = true }
            )
            // `@GestureState` restores itself when the gesture ends or is
            // cancelled, which is what turns "lift the finger" into "no layer
            // is held" without any cleanup of our own.
            .onChange(of: isPressed) { _, pressed in onPressChanged(pressed) }
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityActions {
                Button(action: onSelect) { Text("editor.layer.select", bundle: .module) }
                // The double tap has to have a non-gesture twin (§19), and it
                // means something different per kind.
                if let reopen = reopenLabel {
                    Button(action: onDoubleTap) { Text(reopen, bundle: .module) }
                }
                // Offering Delete on a locked layer would advertise an action
                // the document refuses (FR-087).
                if !layer.isLocked, !isChallengePhoto {
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
    /// What double-tapping this layer would do, or nil where it does nothing.
    private var reopenLabel: LocalizedStringKey? {
        switch layer.content {
        case .text: "editor.layer.edit"
        case .photo: "editor.layer.crop"
        case .sticker, .drawing: nil
        }
    }

    private var accessibilityLabel: Text {
        Text(verbatim: LayerLabel.title(for: layer.content, isChallengePhoto: isChallengePhoto))
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
}
