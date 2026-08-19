import DesignSystem
import SwiftUI

struct PileCardView: View {
    let category: GarmentCategory
    let items: [WardrobeItem]
    let thumbnailData: (WardrobeItem) -> Data?
    let namespace: Namespace.ID
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(category.title, bundle: .module)
                    .font(AppFont.title)
                Text("\(items.count)")
                    .font(.caption)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(AppColor.accent.opacity(0.15)))
            }

            ZStack {
                ForEach(Array(items.prefix(5).enumerated()), id: \.element.id) { index, item in
                    if let data = thumbnailData(item) {
                        DownsampledPhotoView(data: data)
                            .frame(width: 90, height: 90)
                            .rotationEffect(.degrees(pileRotation(for: index)))
                            .offset(pileOffset(for: index))
                            .matchedGeometryEffect(id: item.id, in: namespace)
                            .zIndex(Double(index))
                    }
                }
            }
            .frame(height: 130)
            .frame(maxWidth: .infinity)
        }
        .padding(Spacing.lg)
        .onTapGesture { onTap() }
    }

    private func pileRotation(for index: Int) -> Double {
        let angles: [Double] = [-8, 5, -3, 7, -5]
        return angles[index % angles.count]
    }

    private func pileOffset(for index: Int) -> CGSize {
        let offsets: [CGSize] = [
            CGSize(width: -10, height: 5), CGSize(width: 15, height: -8),
            CGSize(width: -5, height: -12), CGSize(width: 8, height: 10),
            CGSize(width: 0, height: 0),
        ]
        return offsets[index % offsets.count]
    }
}
