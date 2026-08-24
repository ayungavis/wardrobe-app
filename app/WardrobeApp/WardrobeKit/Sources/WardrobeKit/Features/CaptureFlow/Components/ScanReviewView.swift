//
//  ScanReviewView.swift
//  WardrobeKit
//
//  Created by Luisa Haning Tyas on 21/08/26.
//

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
            promoteWeakMatchesToExisting()
        }
    }

    private func promoteWeakMatchesToExisting() {
        for garment in review.garments where garment.decision == .new {
            guard let best = garment.matches.first else { continue }
            review.choose(.existing(best.itemID), for: garment.id)
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
                GarmentScanReviewList(review: review)
                    .padding(Spacing.lg)
            }
        }
    }
}

struct GarmentScanReviewList: View {
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

struct GarmentScanSectionView: View {
    let garment: ScannedGarment
    let review: GarmentReviewModel

    @State private var searchQuery = ""

    private var isExisting: Bool {
        if case .existing = garment.decision {
            return true
        }
        return false
    }

    private var wardrobeItems: [WardrobeItem] {
        review.wardrobeItems(in: garment.category)
    }

    private var filteredItems: [WardrobeItem] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return wardrobeItems }
        return wardrobeItems.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(garment.category.title, bundle: .module)
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)

            thumbnail
            modeToggle

            if isExisting {
                itemGrid
                searchField
            }
        }
    }

    private var thumbnail: some View {
        ZStack(alignment: .bottomTrailing) {
            if let data = review.thumbnailData(forFile: garment.cutoutFile) {
                DownsampledPhotoView(data: data)
                    .frame(width: 140, height: 140)
                    .background(AppColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppColor.surface)
                    .frame(width: 140, height: 140)
            }

            Button {
                withAnimation(.snappy) {
                    review.choose(.discard, for: garment.id)
                }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(AppColor.textPrimary)
                    .padding(Spacing.sm)
                    .background(Circle().fill(.white))
            }
            .buttonStyle(.plain)
            .padding(Spacing.xs)
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 4) {
            toggleButton(title: "capture.scanReview.newItem", isSelected: !isExisting) {
                review.choose(.new, for: garment.id)
            }
            toggleButton(title: "capture.scanReview.existingItem", isSelected: isExisting) {
                let target = garment.matches.first?.itemID ?? wardrobeItems.first?.id
                if let target {
                    review.choose(.existing(target), for: garment.id)
                }
            }
        }
        .padding(4)
        .background(Capsule().fill(AppColor.surface))
    }

    private func toggleButton(
        title: LocalizedStringKey,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? AppColor.accent : AppColor.textSecondary)

                Text(title, bundle: .module)
                    .font(AppFont.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(AppColor.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .padding(.horizontal, Spacing.md)
            .background {
                if isSelected {
                    Capsule()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var itemGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.sm), count: 4),
            spacing: Spacing.sm
        ) {
            ForEach(filteredItems) { item in
                gridCell(for: item)
            }
        }
    }

    private func gridCell(for item: WardrobeItem) -> some View {
        let isSelected = garment.decision == .existing(item.id)
        return Button {
            review.choose(.existing(item.id), for: garment.id)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let data = review.thumbnailData(forItemID: item.id) {
                        DownsampledPhotoView(data: data)
                    } else {
                        RoundedRectangle(cornerRadius: 8).fill(AppColor.surface)
                    }
                }
                .aspectRatio(1, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.caption)
                    .foregroundStyle(isSelected ? AppColor.accent : AppColor.textSecondary)
                    .padding(4)
                    .background(Circle().fill(.white))
                    .padding(4)
            }
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: Spacing.sm) {
            TextField(String(localized: "capture.scanReview.search", bundle: .module), text: $searchQuery)
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(Spacing.sm)
        .background(RoundedRectangle(cornerRadius: 8).fill(AppColor.surface))
    }
}
