import DesignSystem
import SwiftUI
#if os(iOS)
    import UIKit
#endif

/// The drawing tool's own bar, anchored at the bottom where the review drawer
/// and the Save/Share/✓ row sit when no tool is open.
struct DrawingToolbarView: View {
    let pen: DrawingPen
    let canClear: Bool
    let onSelectColor: (DrawingColor) -> Void
    let onSelectWidth: (DrawingWidth) -> Void
    let onToggleEraser: () -> Void
    let onClear: () -> Void
    let onCancel: () -> Void
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            iconButton("xmark", label: Text("common.cancel", bundle: .module),
                       identifier: "editor.drawing.cancel", action: onCancel)

            divider

            colorMenu
            widthMenu

            // Shows the tool it would switch *to*, so the button is an offer
            // rather than a status light.
            iconButton(
                pen.isErasing ? "pencil.tip" : "eraser.fill",
                label: Text(pen.isErasing ? "editor.drawing.pen" : "editor.drawing.eraser", bundle: .module),
                identifier: "editor.drawing.eraser",
                tint: pen.isErasing ? AppColor.accent : AppColor.onMedia,
                action: onToggleEraser
            )

            iconButton(
                "trash",
                label: Text("editor.drawing.clear", bundle: .module),
                identifier: "editor.drawing.clear",
                tint: canClear ? AppColor.destructive : AppColor.onMedia.opacity(0.36),
                haptic: .removed,
                action: onClear
            )
            .disabled(!canClear)

            divider

            iconButton("checkmark", label: Text("common.done", bundle: .module),
                       identifier: "editor.drawing.done", tint: AppColor.accent,
                       haptic: .success, action: onDone)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(AppColor.mediaBackground.opacity(0.82), in: .capsule)
        .overlay { Capsule().stroke(AppColor.onMedia.opacity(0.12), lineWidth: 1) }
    }

    private var divider: some View {
        Rectangle()
            .fill(AppColor.onMedia.opacity(0.14))
            .frame(width: 1, height: 24)
            .accessibilityHidden(true)
    }

    private var colorMenu: some View {
        Menu {
            ForEach(DrawingColor.allCases, id: \.rawValue) { color in
                Button {
                    onSelectColor(color)
                } label: {
                    Label {
                        Text(verbatim: color.name)
                    } icon: {
                        swatchIcon(color)
                    }
                }
            }
        } label: {
            Circle()
                .fill(pen.color.color)
                .frame(width: 23, height: 23)
                .overlay { Circle().stroke(AppColor.onMedia.opacity(0.72), lineWidth: 1.5) }
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("editor.drawing.colorLabel", bundle: .module))
        .accessibilityValue(Text(verbatim: pen.color.name))
        .accessibilityIdentifier("editor.drawing.color")
    }

    /// A rasterised swatch rather than an SF Symbol. UIKit renders menu-item
    /// images as templates — it recolours them with the menu's tint and ignores
    /// `.foregroundStyle` — so a symbol comes out the same colour for all eight
    /// entries. `.original` on a drawn image is what keeps the palette.
    @ViewBuilder
    private func swatchIcon(_ color: DrawingColor) -> some View {
        #if os(iOS)
            Image(uiImage: DrawingSwatchImage.make(color, isSelected: pen.color == color))
                .renderingMode(.original)
        #else
            Image(systemName: pen.color == color ? "checkmark.circle.fill" : "circle.fill")
        #endif
    }

    private var widthMenu: some View {
        Menu {
            ForEach(DrawingWidth.allCases, id: \.rawValue) { width in
                Button {
                    onSelectWidth(width)
                } label: {
                    Label {
                        Text(verbatim: width.name)
                    } icon: {
                        Image(systemName: pen.width == width ? "checkmark" : "minus")
                    }
                }
            }
        } label: {
            Capsule()
                .fill(AppColor.onMedia)
                .frame(width: 24, height: previewHeight)
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("editor.drawing.widthLabel", bundle: .module))
        .accessibilityValue(Text(verbatim: pen.width.name))
        .accessibilityIdentifier("editor.drawing.width")
    }

    private var previewHeight: CGFloat {
        switch pen.width {
        case .thin: 2
        case .medium: 5
        case .thick: 9
        }
    }

    private func iconButton(
        _ systemName: String,
        label: Text,
        identifier: String,
        tint: Color = AppColor.onMedia,
        haptic: EditorHaptics = .selection,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            haptic.play()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

#if os(iOS)
    /// Draws the menu swatch by hand, because a template image cannot carry a
    /// palette. Not extracted into a named utility: `UIGraphicsImageRenderer`
    /// does not exist on macOS, where the tests run, so it has exactly one
    /// caller and no way to be checked by an assertion.
    private enum DrawingSwatchImage {
        static func make(_ color: DrawingColor, isSelected: Bool) -> UIImage {
            let side: CGFloat = 20
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))

            let image = renderer.image { context in
                let disc = CGRect(x: 1, y: 1, width: side - 2, height: side - 2)
                UIColor(color.color).setFill()
                context.cgContext.fillEllipse(in: disc)

                UIColor(color.contrastInk).withAlphaComponent(0.38).setStroke()
                context.cgContext.strokeEllipse(in: disc)

                guard isSelected else { return }

                let tick = UIBezierPath()
                tick.move(to: CGPoint(x: 5.2, y: 10.2))
                tick.addLine(to: CGPoint(x: 8.4, y: 13.3))
                tick.addLine(to: CGPoint(x: 14.8, y: 6.8))
                tick.lineWidth = 2.2
                tick.lineCapStyle = .round
                tick.lineJoinStyle = .round
                UIColor(color.contrastInk).withAlphaComponent(0.82).setStroke()
                tick.stroke()
            }

            return image.withRenderingMode(.alwaysOriginal)
        }
    }
#endif
