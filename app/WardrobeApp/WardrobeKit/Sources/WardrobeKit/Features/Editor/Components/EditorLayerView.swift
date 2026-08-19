import CoreGraphics
import DesignSystem
import SwiftUI

struct EditorLayerView: View {
    let layer: EditorLayer
    let canvasSize: CGSize
    let transform: ElementTransform
    let photo: (String) -> CGImage?
    let isSelected: Bool
    let isOverDeleteTarget: Bool
    let isChallengePhoto: Bool
    let onSelect: () -> Void
    let onDoubleTap: () -> Void
    let onPressChanged: (Bool) -> Void
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
            // Zero distance so a finger that never moves still latches the layer;
            // simultaneous so it does not swallow the two taps above.
            .simultaneousGesture(
                DragGesture(minimumDistance: 0).updating($isPressed) { _, state, _ in state = true }
            )
            // `@GestureState` restores itself on end or cancel, which is what
            // turns "lift the finger" into "no layer is held".
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

    private var settleAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.2)
    }

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

    private var outlineColor: Color {
        if isOverDeleteTarget {
            return AppColor.destructive
        }
        return layer.isLocked ? AppColor.warning : AppColor.accent
    }

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
