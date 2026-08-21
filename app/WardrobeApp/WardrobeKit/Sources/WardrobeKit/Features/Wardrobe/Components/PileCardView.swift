import DesignSystem
import SwiftUI

struct PileCardView: View {
    let category: GarmentCategory
    let items: [WardrobeItem]
    let thumbnailData: (WardrobeItem) -> Data?
    let namespace: Namespace.ID
    let onTap: () -> Void

    @State private var isFannedOut = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(category.title, bundle: .module)
                    .font(AppFont.roundedTitle)
                Text("\(items.count)")
                    .font(AppFont.roundedCaption)
                    .foregroundStyle(AppColor.accent)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(AppColor.surface))
            }
            .padding(.vertical, Spacing.md)

            ZStack {
                ForEach(Array(items.prefix(5).enumerated()), id: \.element.id) { index, item in
                    if let data = thumbnailData(item) {
                        DownsampledPhotoView(data: data)
                            .scaledToFit()
                            .frame(maxHeight: .infinity)
                            .rotationEffect(.degrees(isFannedOut ? pileRotation(for: index) : 0))
                            .offset(isFannedOut ? pileOffset(for: index) : .zero)
                            .matchedGeometryEffect(id: item.id, in: namespace)
                            .zIndex(Double(index))
                            .animation(
                                .spring(response: 0.4, dampingFraction: 0.6)
                                    .delay(Double(index) * 0.08),
                                value: isFannedOut
                            )
                    }
                }
            }
            .frame(height: 130)
            .frame(maxWidth: .infinity)
        }
        .padding(Spacing.lg)
        .onTapGesture { onTap() }
        .task {
            isFannedOut = false
            try? await Task.sleep(for: .seconds(0.3))
            isFannedOut = true
        }
        .onDisappear {
            isFannedOut = false
        }
    }

    private func pileRotation(for index: Int) -> Double {
        let angles: [Double] = [-18, 15, -13, 17, -15]
        return angles[index % angles.count]
    }

    private func pileOffset(for index: Int) -> CGSize {
        let offsets: [CGSize] = [
            CGSize(width: -40, height: 35), CGSize(width: 45, height: -38),
            CGSize(width: -35, height: -42), CGSize(width: 38, height: 40),
            CGSize(width: 0, height: 0),
        ]
        return offsets[index % offsets.count]
    }
}
