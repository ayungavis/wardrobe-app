import DesignSystem
import SwiftUI

/// Story-style text composer: dimmed backdrop, a vertical size slider down the
/// left edge, the live-styled field in the middle, and font / colour /
/// background / alignment controls above the keyboard.
///
/// Everything writes to the tool's working copy, so Cancel still restores the
/// last committed state (FR-019) and dragging the slider never touches the
/// committed draft.
struct TextComposerOverlay: View {
    let working: TextItem
    let isExisting: Bool
    let onUpdate: (TextItem) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void
    let onDone: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            AppColor.mediaBackground.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture(perform: onDone)

            VStack(spacing: 0) {
                composerBar

                HStack(spacing: Spacing.md) {
                    TextSizeSlider(scale: working.scale) { newScale in
                        var updated = working
                        updated.scale = newScale
                        onUpdate(updated)
                    }

                    field
                }
                .padding(.horizontal, Spacing.lg)
                .frame(maxHeight: .infinity)

                TextStyleBar(working: working, onUpdate: onUpdate)
            }
        }
        .task { isFocused = true }
    }

    private var composerBar: some View {
        HStack {
            Button(action: onCancel) {
                Text("common.cancel", bundle: .module)
                    .frame(minHeight: 44)
            }

            Spacer()

            if isExisting {
                // Accessible deletion path — drag-to-trash needs a drag.
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text("challenge.abandon.confirm.action", bundle: .module))
            }

            Button(action: onDone) {
                Text("common.done", bundle: .module)
                    .bold()
                    .frame(minHeight: 44)
            }
        }
        .foregroundStyle(AppColor.onMedia)
        .padding(.horizontal, Spacing.lg)
    }

    private var field: some View {
        TextField(
            String(localized: "editor.text.placeholder", bundle: .module),
            text: Binding(
                get: { working.content },
                set: { newValue in
                    var updated = working
                    updated.content = newValue
                    onUpdate(updated)
                }
            ),
            axis: .vertical
        )
        .font(.system(size: 34 * working.scale, weight: working.fontStyle.weight, design: working.fontStyle.design))
        .multilineTextAlignment(working.alignmentStyle.textAlignment)
        .foregroundStyle(working.hasBackground ? working.textColor.contrastText : working.textColor.color)
        .focused($isFocused)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background {
            if working.hasBackground {
                RoundedRectangle(cornerRadius: 12).fill(working.textColor.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: working.alignmentStyle.frameAlignment)
    }
}

/// Vertical size slider, Instagram's signature text control.
private struct TextSizeSlider: View {
    let scale: CGFloat
    let onChange: (CGFloat) -> Void

    private static let range: ClosedRange<CGFloat> = 0.5 ... 3
    private static let trackHeight: CGFloat = 220

    var body: some View {
        Capsule()
            .fill(AppColor.onMedia.opacity(0.25))
            .frame(width: 4, height: Self.trackHeight)
            .overlay(alignment: .top) {
                Circle()
                    .fill(AppColor.onMedia)
                    .frame(width: 22, height: 22)
                    .offset(y: knobOffset)
            }
            .frame(width: 44, height: Self.trackHeight) // 44pt touch target
            .contentShape(.rect)
            .gesture(dragGesture)
            .accessibilityLabel(Text("editor.text.size", bundle: .module))
            .accessibilityValue(Text(verbatim: "\(Int(scale * 100))%"))
            .accessibilityAdjustableAction { direction in
                let step: CGFloat = direction == .increment ? 0.1 : -0.1
                onChange(min(Self.range.upperBound, max(Self.range.lowerBound, scale + step)))
            }
    }

    /// Largest sits at the top, like the built-in story editors.
    private var knobOffset: CGFloat {
        let span = Self.range.upperBound - Self.range.lowerBound
        let progress = (scale - Self.range.lowerBound) / span
        return (1 - progress) * (Self.trackHeight - 22)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let progress = 1 - min(1, max(0, value.location.y / Self.trackHeight))
                let span = Self.range.upperBound - Self.range.lowerBound
                onChange(Self.range.lowerBound + progress * span)
            }
    }
}

/// Font chips, colour swatches, background and alignment toggles.
private struct TextStyleBar: View {
    let working: TextItem
    let onUpdate: (TextItem) -> Void

    var body: some View {
        VStack(spacing: Spacing.sm) {
            fontRow
            HStack(spacing: Spacing.md) {
                backgroundToggle
                alignmentToggle
                colorRow
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.sm)
    }

    private var fontRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(TextFontStyle.allCases, id: \.rawValue) { style in
                    Button {
                        var updated = working
                        updated.fontName = style.rawValue
                        onUpdate(updated)
                    } label: {
                        Text(verbatim: style.sampleLabel)
                            .font(.system(size: 15, weight: style.weight, design: style.design))
                            .foregroundStyle(isSelected(style) ? AppColor.mediaBackground : AppColor.onMedia)
                            .padding(.horizontal, Spacing.md)
                            .frame(height: 34)
                            .background(isSelected(style) ? AppColor.onMedia : AppColor.onMedia.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    .accessibilityLabel(Text(verbatim: style.rawValue))
                    .accessibilityAddTraits(isSelected(style) ? [.isSelected] : [])
                }
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    private var backgroundToggle: some View {
        Button {
            var updated = working
            updated.hasBackground.toggle()
            onUpdate(updated)
        } label: {
            Image(systemName: working.hasBackground ? "a.square.fill" : "a.square")
                .font(.system(size: 24))
                .foregroundStyle(AppColor.onMedia)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(Text("editor.text.background", bundle: .module))
    }

    private var alignmentToggle: some View {
        Button {
            var updated = working
            updated.alignmentName = working.alignmentStyle.next.rawValue
            onUpdate(updated)
        } label: {
            Image(systemName: working.alignmentStyle.symbolName)
                .font(.system(size: 20))
                .foregroundStyle(AppColor.onMedia)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(Text("editor.text.alignment", bundle: .module))
    }

    private var colorRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(TextColor.allCases, id: \.rawValue) { paletteColor in
                    Button {
                        var updated = working
                        updated.colorName = paletteColor.rawValue
                        onUpdate(updated)
                    } label: {
                        Circle()
                            .fill(paletteColor.color)
                            .frame(width: isSelected(paletteColor) ? 34 : 26)
                            .overlay {
                                Circle().strokeBorder(AppColor.onMedia, lineWidth: isSelected(paletteColor) ? 3 : 1)
                            }
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(Text(verbatim: paletteColor.rawValue))
                    .accessibilityAddTraits(isSelected(paletteColor) ? [.isSelected] : [])
                }
            }
        }
    }

    private func isSelected(_ style: TextFontStyle) -> Bool {
        working.fontStyle == style
    }

    private func isSelected(_ color: TextColor) -> Bool {
        working.textColor == color
    }
}
