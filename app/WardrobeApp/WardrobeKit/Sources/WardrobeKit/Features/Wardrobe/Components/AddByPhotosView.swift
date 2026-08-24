import DesignSystem
import PhotosUI
import SwiftUI

struct AddByPhotosView: View {
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
                }

                GarmentReviewListView(review: review, showsWearDate: true)

                if review.isMissingAWearDate {
                    Text("wardrobe.review.wearDate.held", bundle: .module)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .navigationTitle(Text("wardrobe.add.photos.title", bundle: .module))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            review.commitImported()
                            if review.garments.isEmpty {
                                dismiss()
                            }
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
