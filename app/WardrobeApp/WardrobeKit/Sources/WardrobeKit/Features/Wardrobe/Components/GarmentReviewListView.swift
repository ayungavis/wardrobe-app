import DesignSystem
import SwiftUI

struct GarmentReviewListView: View {
    let review: GarmentReviewModel
    var allowsMatching: Bool = true
    var showsWearDate = false

    var body: some View {
        ForEach(review.garments) { garment in
            VStack(alignment: .leading, spacing: Spacing.md) {
                ScannedGarmentRowView(
                    garment: garment,
                    scannedImage: review.thumbnailData(forFile: garment.cutoutFile),
                    candidateImage: { review.thumbnailData(forItemID: $0) },
                    allowsMatching: allowsMatching,
                    onChoose: { review.choose($0, for: garment.id) }
                )

                if showsWearDate, garment.decision != .discard {
                    WearDateRowView(wornAt: garment.wornAt) {
                        review.setWornAt($0, for: garment.id)
                    }
                }
            }
        }
    }
}
