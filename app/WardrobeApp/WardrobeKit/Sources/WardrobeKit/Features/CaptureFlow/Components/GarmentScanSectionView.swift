import DesignSystem
import SwiftUI

struct GarmentScanSectionView: View {
    let garment: ScannedGarment
    let review: GarmentReviewModel

    @State private var searchQuery = ""

    private var isExisting: Bool {
        if case .existing = garment.decision {
            return true
        }
        return false
    }

    private var wardrobeItems: [WardrobeItem] {
        review.wardrobeItems(in: garment.category)
    }

    private var filteredItems: [WardrobeItem] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return wardrobeItems }
        return wardrobeItems.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(garment.category.title, bundle: .module)
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)

            thumbnail
            modeToggle

            if isExisting {
                itemGrid
                searchField
            }
        }
    }

    private var thumbnail: some View {
        ZStack(alignment: .bottomTrailing) {
            if let data = review.thumbnailData(forFile: garment.cutoutFile) {
                DownsampledPhotoView(data: data)
                    .frame(width: 140, height: 140)
                    .background(AppColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppColor.surface)
                    .frame(width: 140, height: 140)
            }

            Button {
                withAnimation(.snappy) {
                    review.choose(.discard, for: garment.id)
                }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(AppColor.textPrimary)
                    .padding(Spacing.sm)
                    .background(Circle().fill(AppColor.onMedia))
            }
            .buttonStyle(.plain)
            .padding(Spacing.xs)
        }
    }

    private var modeToggle: some View {
        HStack(spacing: Spacing.xs) {
            toggleButton(title: "capture.scanReview.newItem", isSelected: !isExisting) {
                review.choose(.new, for: garment.id)
            }
            toggleButton(title: "capture.scanReview.existingItem", isSelected: isExisting) {
                let target = garment.matches.first?.itemID ?? wardrobeItems.first?.id
                if let target {
                    review.choose(.existing(target), for: garment.id)
                }
            }
        }
        .padding(Spacing.xs)
        .background(Capsule().fill(AppColor.surface))
    }

    private func toggleButton(
        title: LocalizedStringKey,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? AppColor.accent : AppColor.textSecondary)

                Text(title, bundle: .module)
                    .font(AppFont.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(AppColor.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .padding(.horizontal, Spacing.md)
            .background {
                if isSelected {
                    Capsule()
                        .fill(AppColor.onMedia)
                        .appShadow(.card)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var itemGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.sm), count: 4),
            spacing: Spacing.sm
        ) {
            ForEach(filteredItems) { item in
                gridCell(for: item)
            }
        }
    }

    private func gridCell(for item: WardrobeItem) -> some View {
        let isSelected = garment.decision == .existing(item.id)
        return Button {
            review.choose(.existing(item.id), for: garment.id)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let data = review.thumbnailData(forItemID: item.id) {
                        DownsampledPhotoView(data: data)
                    } else {
                        RoundedRectangle(cornerRadius: 8).fill(AppColor.surface)
                    }
                }
                .aspectRatio(1, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(AppFont.caption)
                    .foregroundStyle(isSelected ? AppColor.accent : AppColor.textSecondary)
                    .padding(Spacing.xs)
                    .background(Circle().fill(AppColor.onMedia))
                    .padding(Spacing.xs)
            }
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: Spacing.sm) {
            TextField(String(localized: "capture.scanReview.search", bundle: .module), text: $searchQuery)
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(Spacing.sm)
        .background(RoundedRectangle(cornerRadius: 8).fill(AppColor.surface))
    }
}
