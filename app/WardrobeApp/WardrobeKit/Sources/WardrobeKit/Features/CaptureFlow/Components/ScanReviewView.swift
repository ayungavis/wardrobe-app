import DesignSystem
import SwiftUI

struct ScanReviewView: View {
    let review: GarmentReviewModel
    let onRetake: () -> Void
    let onContinue: () -> Void

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("capture.scanReview.title", bundle: .module))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: onRetake) {
                            Text("capture.scanReview.retake", bundle: .module)
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: onContinue) {
                            Text("capture.scanReview.continueToEdit", bundle: .module)
                        }
                        .disabled(review.isScanning || review.garments.isEmpty)
                    }
                }
        }
        .task(id: review.isScanning) {
            guard !review.isScanning else { return }
            review.promoteConfidentMatches()
        }
    }

    @ViewBuilder
    private var content: some View {
        if review.isScanning {
            ProgressView {
                Text("wardrobe.scan.processing", bundle: .module)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if review.garments.isEmpty {
            ContentUnavailableView {
                Label { Text("wardrobe.scan.empty", bundle: .module) } icon: {
                    Image(systemName: "tshirt")
                }
            } actions: {
                Button(action: onRetake) {
                    Text("wardrobe.scan.retake", bundle: .module)
                }
            }
        } else {
            ScrollView {
                GarmentScanReviewListView(review: review)
                    .padding(Spacing.lg)
            }
        }
    }
}
