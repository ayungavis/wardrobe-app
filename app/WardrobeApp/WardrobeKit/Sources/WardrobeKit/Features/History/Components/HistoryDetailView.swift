import DesignSystem
import SwiftUI

public struct HistoryDetailView: View {
    public let completion: CompletedChallenge
    public let photoData: Data?
    let viewModel: HistoryViewModel

    @State private var garments: [(item: WardrobeItem, wearCount: Int)] = []

    public init(completion: CompletedChallenge, photoData: Data?, viewModel: HistoryViewModel) {
        self.completion = completion
        self.photoData = photoData
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            // Main Background
            Image("appBG", bundle: .module)
                .resizable()
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                ZStack(alignment: .top) {
                    // Main Content Stack
                    VStack(spacing: 0) {
                        // 1. Top Canvas / Polaroid
                        HistoryPolaroidCardView(
                            completion: completion,
                            photoData: photoData
                        )
                        .padding(.horizontal, Spacing.lg)
                        .padding(.top, Spacing.lg)
                        .zIndex(2)
                        .frame(width: 345, height: 614)

                        // 2. Receipt Card Background + Content
                        receiptContent
                            .padding(.horizontal, Spacing.lg)
                            .zIndex(1)
                            .frame(width: 345, height: 465)
                    }
                }
            }
        }
        .task { garments = viewModel.garmentsWorn(in: completion) }
        .navigationTitle(Text("tab.history", bundle: .module))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var receiptContent: some View {
        // Layer the text content directly over your existing receipt paper asset
        ZStack(alignment: .top) {
            // Your custom torn paper asset
            Image("TornReceipt", bundle: .module)
                .resizable()

            VStack(alignment: .leading, spacing: 16) {
                // Header Info
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        label("history.detail.date")
                        Text(completion.completedAt, format: .dateTime.day().month(.wide).year())
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        label("history.detail.description")
                        Text(completion.card.prompt)
                            .font(.body)
                            .foregroundColor(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // If your dotted line is a separate asset, place it here:

                wearSection
            }
            // Adjust these paddings to match the inner safe area of your specific receipt asset
            .padding(.horizontal, Spacing.sm)
            .padding(.top, Spacing.xxl)
        }
    }

    private var wearSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("history.detail.wear")

            if garments.isEmpty {
                Text("history.detail.garments.empty", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            } else {
                HStack(spacing: 16) {
                    ForEach(garments, id: \.item.id) { entry in
                        garmentView(item: entry.item, wearCount: entry.wearCount)
                    }
                }
            }
        }
        .padding(.bottom, 24)
    }

    private func garmentView(item: WardrobeItem, wearCount: Int) -> some View {
        VStack(spacing: 8) {
            if let data = viewModel.thumbnailData(for: item) {
                DownsampledPhotoView(data: data)
                    .frame(width: 130, height: 130)

            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppColor.surface)
                    .frame(width: 80, height: 80)
            }
            Text("wardrobe.wearCount \(wearCount)", bundle: .module)
                .font(.subheadline)
                .bold()
                .foregroundColor(.black)
        }
    }

    /// The receipt prints "Field :" runs; the colon is layout, so it stays out
    /// of the catalogue and off the translators' plate.
    private func label(_ key: LocalizedStringKey) -> Text {
        Text(key, bundle: .module).bold() + Text(verbatim: " :").bold()
    }
}
