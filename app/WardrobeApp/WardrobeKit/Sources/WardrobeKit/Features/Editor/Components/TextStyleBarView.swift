import DesignSystem
import SwiftUI

/// The composer's bottom panel: alignment, background style, the character
/// counter, the font chips, and the colour swatches.
struct TextStyleBarView: View {
    @Binding var content: TextContent

    var body: some View {
        VStack(spacing: Spacing.md) {
            controlRow
            fontRow
            colorRow
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.md)
        .background(AppColor.mediaBackground.opacity(0.88))
        .clipShape(.rect(topLeadingRadius: 22, topTrailingRadius: 22))
    }

    // MARK: Alignment, background, counter

    private var controlRow: some View {
        HStack(spacing: Spacing.sm) {
            iconButton(
                systemName: content.alignmentStyle.symbolName,
                label: Text("editor.text.alignment", bundle: .module),
                value: nil,
                identifier: "editor.text.alignment"
            ) {
                content.alignmentName = content.alignmentStyle.next.rawValue
            }

            backgroundButton

            Spacer()

            Text(
                "editor.text.counter \(content.content.count) \(EditorViewModel.maximumTextLength)",
                bundle: .module
            )
            .font(AppFont.caption.monospacedDigit())
            .foregroundStyle(AppColor.onMedia.opacity(0.64))
        }
    }

    /// Shows the style it will produce rather than naming it: an "A" on the
    /// pill you are about to get.
    private var backgroundButton: some View {
        Button {
            content.backgroundStyleName = content.backgroundStyle.next.rawValue
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(backgroundSwatchFill)
                    .frame(width: 26, height: 26)

                Text(verbatim: "A")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(
                        content.backgroundStyle == .solid ? AppColor.mediaBackground : AppColor.onMedia
                    )
            }
            .frame(width: 42, height: 36)
            .background(AppColor.onMedia.opacity(0.10), in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("editor.text.background", bundle: .module))
        .accessibilityValue(Text(verbatim: content.backgroundStyle.name))
        .accessibilityIdentifier("editor.text.background")
    }

    private var backgroundSwatchFill: Color {
        switch content.backgroundStyle {
        case .none: .clear
        case .solid: AppColor.onMedia
        case .translucent: AppColor.onMedia.opacity(0.28)
        }
    }

    // MARK: Fonts

    private var fontRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.sm) {
                ForEach(TextFontStyle.allCases, id: \.rawValue) { style in
                    let isSelected = content.fontStyle == style
                    Button {
                        content.fontName = style.rawValue
                    } label: {
                        // Each chip is set in the face it names, so the row is
                        // its own specimen sheet.
                        Text(verbatim: style.name)
                            .font(.system(size: 13, weight: style.weight, design: style.design))
                            .padding(.horizontal, Spacing.md)
                            .frame(height: 36)
                            .background(
                                isSelected ? AppColor.onMedia : AppColor.onMedia.opacity(0.10),
                                in: .capsule
                            )
                            .foregroundStyle(isSelected ? AppColor.mediaBackground : AppColor.onMedia)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: style.name))
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    .accessibilityIdentifier("editor.font.\(style.rawValue)")
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Colours

    private var colorRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.lg) {
                ForEach(TextColor.allCases, id: \.rawValue) { paletteColor in
                    let isSelected = content.textColor == paletteColor
                    Button {
                        content.colorName = paletteColor.rawValue
                    } label: {
                        Circle()
                            .fill(paletteColor.color)
                            .frame(width: 30, height: 30)
                            .overlay {
                                Circle()
                                    .stroke(AppColor.onMedia, lineWidth: isSelected ? 3 : 0)
                                    .padding(-4)
                            }
                            .overlay {
                                Circle().stroke(AppColor.onMedia.opacity(0.28), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .frame(width: 40, height: 40)
                    .accessibilityLabel(Text(verbatim: paletteColor.name))
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    .accessibilityIdentifier("editor.color.\(paletteColor.rawValue)")
                }
            }
            .padding(.horizontal, Spacing.xs)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Helpers

    private func iconButton(
        systemName: String,
        label: Text,
        value: Text?,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 42, height: 36)
                .background(AppColor.onMedia.opacity(0.10), in: .rect(cornerRadius: 10))
                .foregroundStyle(AppColor.onMedia)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(value ?? Text(verbatim: ""))
        .accessibilityIdentifier(identifier)
    }
}
