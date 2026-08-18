import DesignSystem
import SwiftUI

/// The fixed canvas background palette (FR-091).
///
/// A short sheet with a horizontal strip of swatches, so most of the canvas
/// stays visible behind it and picking never dismisses: choosing a background
/// is comparing it against the picture, not guessing from a thumbnail. Only
/// Done — or a drag — closes it.
struct BackgroundPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let onPick: (CanvasBackground) -> Void

    /// Seeded from the document, then owned here. The checkmark has to move on
    /// the same frame as the tap, and that cannot depend on when SwiftUI
    /// re-evaluates the sheet's closure. Nothing else can change the background
    /// while this is open, so the two cannot drift.
    @State private var selected: CanvasBackground

    init(selected: CanvasBackground, onPick: @escaping (CanvasBackground) -> Void) {
        self.onPick = onPick
        _selected = State(initialValue: selected)
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            header
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.lg)

            ScrollView(.horizontal) {
                HStack(spacing: Spacing.md) {
                    ForEach(CanvasBackground.allCases) { background in
                        swatchButton(background)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.lg)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("editor.background.title", bundle: .module)
                    .font(AppFont.body.weight(.semibold))
                    .foregroundStyle(AppColor.onMedia)

                Text("editor.background.subtitle", bundle: .module)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.onMedia.opacity(0.64))
            }

            Spacer()

            Button(action: dismiss.callAsFunction) {
                Text("common.done", bundle: .module)
                    .font(AppFont.body.weight(.bold))
                    .foregroundStyle(AppColor.onMedia)
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
            }
        }
    }

    private func swatchButton(_ background: CanvasBackground) -> some View {
        Button {
            selected = background
            onPick(background)
        } label: {
            VStack(spacing: Spacing.sm) {
                swatch(background)

                Text(verbatim: background.name)
                    .font(AppFont.caption.weight(.semibold))
                    .foregroundStyle(
                        background == selected ? AppColor.onMedia : AppColor.onMedia.opacity(0.64)
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: background.name))
        .accessibilityAddTraits(background == selected ? [.isSelected] : [])
        .accessibilityIdentifier("editor.background.\(background.rawValue)")
    }

    private func swatch(_ background: CanvasBackground) -> some View {
        CanvasBackgroundView(background: background)
            .frame(width: 58, height: 92)
            .clipShape(.rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        background == selected ? AppColor.onMedia : AppColor.onMedia.opacity(0.16),
                        lineWidth: background == selected ? 3 : 1
                    )
            }
            .overlay(alignment: .topTrailing) {
                if background == selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(AppColor.mediaBackground, AppColor.onMedia)
                        .padding(Spacing.xs)
                }
            }
    }
}
