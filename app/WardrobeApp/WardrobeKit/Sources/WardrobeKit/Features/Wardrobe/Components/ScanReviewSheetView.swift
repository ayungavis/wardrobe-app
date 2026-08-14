import DesignSystem
import SwiftUI

/// Confirms a whole batch at once. A twenty-photo scan can produce forty
/// garments, and interrupting the scan for each one would be unusable — so the
/// decisions are collected and reviewed in a single pass.
struct ScanReviewSheetView: View {
    let garments: [ScannedGarment]
    let thumbnail: (String) -> Data?
    let itemThumbnail: (UUID) -> Data?
    let onChoose: (UUID, ScannedGarment.Decision) -> Void
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List(garments) { garment in
                ScannedGarmentRowView(
                    garment: garment,
                    scannedImage: thumbnail(garment.cutoutFile),
                    candidateImage: itemThumbnail
                ) { decision in
                    onChoose(garment.id, decision)
                }
            }
            .navigationTitle(Text("wardrobe.review.title", bundle: .module))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: onConfirm) {
                            Text("wardrobe.review.confirm", bundle: .module)
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .cancel, action: onCancel) {
                            Text("common.cancel", bundle: .module)
                        }
                    }
                }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled()
    }
}
