//
//  GarmentDiscardGridView.swift
//  WardrobeKit
//
//  Created by Luisa Haning Tyas on 23/08/26.
//


import DesignSystem
import SwiftUI

struct GarmentDiscardGridView: View {
    let review: GarmentReviewModel

    private var groupedGarments: [(category: GarmentCategory, garments: [ScannedGarment])] {
        let grouped = Dictionary(grouping: review.activeGarments, by: \.category)
        return GarmentCategory.allCases.compactMap { category in
            guard let items = grouped[category], !items.isEmpty else { return nil }
            return (category, items)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            ForEach(groupedGarments, id: \.category) { group in
                categorySection(group.category, garments: group.garments)
            }
        }
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
}

struct GarmentDiscardHeaderView: View {
    let titleKey: LocalizedStringKey
    let messageKey: LocalizedStringKey

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Text(titleKey, bundle: .module)
                .font(AppFont.title.weight(.bold))
                .foregroundStyle(AppColor.textPrimary)
            Text(messageKey, bundle: .module)
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}