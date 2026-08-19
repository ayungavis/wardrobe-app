import SwiftUI

struct GarmentReviewListView: View {
    let review: GarmentReviewModel

    var body: some View {
        ForEach(review.garments) { garment in
            ScannedGarmentRowView(
                garment: garment,
                scannedImage: review.thumbnailData(forFile: garment.cutoutFile),
                candidateImage: { review.thumbnailData(forItemID: $0) },
                onChoose: { review.choose($0, for: garment.id) }
            )
        }
    }
}
