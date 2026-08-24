import DesignSystem
import SwiftUI

struct GarmentScanReviewListView: View {
    let review: GarmentReviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            ForEach(review.garments.filter { $0.decision != .discard }) { garment in
                GarmentScanSectionView(garment: garment, review: review)
            }
        }
        .animation(.snappy, value: review.garments)
    }
}
