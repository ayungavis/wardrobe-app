import DesignSystem
import SwiftUI

/// The categorised sticker catalogue (FR-019).
///
/// Recent leads the row when there is one, because the sticker you want next is
/// usually the one you just used. Picking closes the sheet — one sticker, then
/// straight back to placing it.
struct StickerPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let recentIDs: [String]
    let onPick: (StickerCatalogueEntry) -> Void

    @State private var category: StickerCategory

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.sm), count: 4)

    init(recentIDs: [String], onPick: @escaping (StickerCatalogueEntry) -> Void) {
        self.recentIDs = recentIDs
        self.onPick = onPick
        _category = State(initialValue: recentIDs.isEmpty ? .emoji : .recent)
    }

    var body: some View {
        VStack(spacing: 0) {
            // The sheet draws its own grabber, so the system one is hidden at
            // the call site — otherwise there would be two.
            Capsule()
                .fill(AppColor.onMedia.opacity(0.34))
                .frame(width: 38, height: 5)
                .padding(.top, Spacing.sm)
                .accessibilityHidden(true)

            header
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)

            categoryRow
                .padding(.top, Spacing.md)

            Divider()
                .overlay(AppColor.onMedia.opacity(0.10))
                .padding(.top, Spacing.md)

            grid
        }
        .foregroundStyle(AppColor.onMedia)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("editor.sticker.title", bundle: .module)
                    .font(AppFont.title)

                Text("editor.sticker.subtitle", bundle: .module)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.onMedia.opacity(0.64))
            }

            Spacer()

            Button(action: dismiss.callAsFunction) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(AppColor.onMedia.opacity(0.10), in: .circle)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(Text("common.close", bundle: .module))
            .accessibilityIdentifier("editor.sticker.close")
        }
    }

    private var categoryRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.sm) {
                ForEach(availableCategories) { category in
                    let isSelected = self.category == category
                    Button {
                        self.category = category
                    } label: {
                        Label {
                            Text(verbatim: category.name)
                        } icon: {
                            Image(systemName: category.symbolName)
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, Spacing.md)
                        .frame(height: 36)
                        .background(
                            isSelected ? AppColor.onMedia : AppColor.onMedia.opacity(0.10),
                            in: .capsule
                        )
                        .foregroundStyle(isSelected ? AppColor.mediaBackground : AppColor.onMedia)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: category.name))
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    .accessibilityIdentifier("editor.sticker.category.\(category.rawValue)")
                }
            }
            .padding(.horizontal, Spacing.lg)
        }
        .scrollIndicators(.hidden)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Spacing.md) {
                ForEach(StickerCatalogue.entries(in: category, recentIDs: recentIDs)) { entry in
                    Button {
                        onPick(entry)
                        dismiss()
                    } label: {
                        StickerArtworkView(art: .catalogue(entry.id), size: 64)
                            .frame(maxWidth: .infinity)
                            .frame(height: 70)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: entry.name))
                    .accessibilityIdentifier("editor.sticker.\(entry.id)")
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.lg)
        }
        .scrollIndicators(.hidden)
    }

    /// Recent earns its pill only once there is something in it.
    private var availableCategories: [StickerCategory] {
        recentIDs.isEmpty ? [.emoji, .stickers] : StickerCategory.allCases
    }
}
