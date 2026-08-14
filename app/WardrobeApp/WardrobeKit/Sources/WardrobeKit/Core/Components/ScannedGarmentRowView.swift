import DesignSystem
import SwiftUI

/// One scanned garment and what the user wants done with it.
///
/// The proposal is shown as a **picture next to a picture**: judging whether two
/// garments are the same from a name is guesswork, and matching is never certain
/// enough to decide on the user's behalf (FR-029).
struct ScannedGarmentRowView: View {
    let garment: ScannedGarment
    let scannedImage: Data?
    let candidateImage: (UUID) -> Data?
    let onChoose: (ScannedGarment.Decision) -> Void

    private static let thumbnailSize: CGFloat = 72

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                thumbnail(scannedImage)
                Text(garment.category.title, bundle: .module)
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textPrimary)
            }

            if garment.matches.isEmpty {
                Text("wardrobe.review.newOnly", bundle: .module)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            } else {
                choices
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            choice(
                isSelected: garment.decision == .new,
                label: Text("wardrobe.review.new", bundle: .module),
                image: nil
            ) { onChoose(.new) }

            ForEach(garment.matches) { match in
                choice(
                    isSelected: garment.decision == .existing(match.itemID),
                    label: Text("wardrobe.review.existing", bundle: .module),
                    image: candidateImage(match.itemID)
                ) { onChoose(.existing(match.itemID)) }
            }
        }
    }

    private func choice(
        isSelected: Bool,
        label: Text,
        image: Data?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? AppColor.accent : AppColor.textSecondary)
                if let image {
                    thumbnail(image)
                }
                label
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func thumbnail(_ data: Data?) -> some View {
        if let data {
            DownsampledPhotoView(data: data)
                .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
                .background(AppColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColor.surface)
                .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
        }
    }
}
