import DesignSystem
import PhotosUI
import SwiftUI

/// Fills the wardrobe from a batch of library photos, without completing a
/// challenge. A dev tool: the product path is capture → editor drawer → ✓.
///
/// Reviewing the whole batch in one pass is the point — a twenty-photo scan can
/// find forty garments, and confirming each one mid-scan would be unusable.
struct BulkScanView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var review: GarmentReviewModel
    @State private var selectedPhotos: [PhotosPickerItem] = []

    init(review: GarmentReviewModel) {
        _review = State(wrappedValue: review)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    picker
                } footer: {
                    Text(verbatim: "Scans photos into the wardrobe without completing a challenge.")
                }

                ForEach(review.garments) { garment in
                    ScannedGarmentRowView(
                        garment: garment,
                        scannedImage: review.thumbnailData(forFile: garment.cutoutFile),
                        candidateImage: { review.thumbnailData(forItemID: $0) },
                        onChoose: { review.choose($0, for: garment.id) }
                    )
                }
            }
            .navigationTitle(Text(verbatim: "Bulk scan"))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            review.commit(completionID: nil, at: Date())
                            dismiss()
                        } label: {
                            Text("wardrobe.review.confirm", bundle: .module)
                        }
                        .disabled(review.garments.isEmpty)
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .cancel) {
                            review.cancel()
                            dismiss()
                        } label: {
                            Text("common.cancel", bundle: .module)
                        }
                    }
                }
        }
        .presentationDetents([.large])
    }

    private var picker: some View {
        PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 20, matching: .images) {
            if review.isScanning {
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                    Text("wardrobe.scan.processing", bundle: .module)
                }
            } else {
                Text("wardrobe.scan.add", bundle: .module)
            }
        }
        .disabled(review.isScanning)
        .onChange(of: selectedPhotos) { _, newItems in
            Task { await scan(newItems) }
        }
    }

    private func scan(_ pickerItems: [PhotosPickerItem]) async {
        for item in pickerItems {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            review.scan(photo: data)
        }
    }
}
