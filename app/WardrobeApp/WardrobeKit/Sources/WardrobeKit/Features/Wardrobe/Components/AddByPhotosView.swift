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
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    picker

                    if review.activeGarments.isEmpty, !review.isScanning {
                        GarmentDiscardHeaderView(
                            titleKey: "wardrobe.add.photos.empty.title",
                            messageKey: "wardrobe.add.photos.empty.message"
                        )
                        .padding(.top, Spacing.xxl)
                    } else {
                        GarmentDiscardHeaderView(
                            titleKey: "wardrobe.add.photos.review.title",
                            messageKey: "wardrobe.add.photos.review.message"
                        )

                        if review.isScanning {
                            HStack(spacing: Spacing.sm) {
                                ProgressView()
                                Text("wardrobe.scan.processing", bundle: .module)
                            }
                        }

                        GarmentDiscardGridView(review: review)
                    }

                    if review.isMissingAWearDate {
                        Text("wardrobe.review.wearDate.held", bundle: .module)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }

                    ForEach(review.activeGarments) { garment in
                        WearDateRowView(wornAt: garment.wornAt) {
                            review.setWornAt($0, for: garment.id)
                        }
                    }
                }
                .padding(Spacing.lg)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        review.commitImported()
                        if review.activeGarments.isEmpty {
                            dismiss()
                        }
                    } label: {
                        Text("wardrobe.review.confirm", bundle: .module)
                    }
                    .disabled(review.activeGarments.isEmpty)
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
            Image(systemName: "plus")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                // .padding(.vertical, Spacing.md)
                .background(Capsule().fill(AppColor.accent))
        }
        .disabled(review.isScanning)
        .onChange(of: selectedPhotos) { _, newItems in
            Task { await scan(newItems) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.sm) {
            Text("wardrobe.add.photos.empty.title", bundle: .module)
                .font(AppFont.title.weight(.bold))
                .foregroundStyle(AppColor.textPrimary)
            Text("wardrobe.add.photos.empty.message", bundle: .module)
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.xxl)
    }

    private var header: some View {
        VStack(spacing: Spacing.sm) {
            Text("wardrobe.add.photos.review.title", bundle: .module)
                .font(AppFont.title.weight(.bold))
                .foregroundStyle(AppColor.textPrimary)
            Text("wardrobe.add.photos.review.message", bundle: .module)
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func categorySection(_ category: GarmentCategory, garments: [ScannedGarment]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(category.title, bundle: .module)
                .font(AppFont.body.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(garments) { garment in
                        garmentThumbnail(garment)
                    }
                }
            }
        }
    }

    private func garmentThumbnail(_ garment: ScannedGarment) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let data = review.thumbnailData(forFile: garment.cutoutFile) {
                    DownsampledPhotoView(data: data)
                } else {
                    RoundedRectangle(cornerRadius: 8).fill(AppColor.surface)
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button {
                withAnimation(.snappy) {
                    review.choose(.discard, for: garment.id)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(Circle().fill(.black.opacity(0.6)))
            }
            .buttonStyle(.plain)
            .padding(4)
        }
    }

    private func scan(_ pickerItems: [PhotosPickerItem]) async {
        for item in pickerItems {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            review.scan(photo: data)
        }
    }
}
