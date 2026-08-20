import DesignSystem
import SwiftUI

public struct HistoryDetailView: View {
    public let completion: CompletedChallenge
    public let previewData: Data?
    let viewModel: HistoryViewModel

    let onSelectGarment: (UUID) -> Void

    @State private var garments: [(item: WardrobeItem, wearCount: Int)] = []

    public init(
        completion: CompletedChallenge,
        previewData: Data?,
        viewModel: HistoryViewModel,
        onSelectGarment: @escaping (UUID) -> Void
    ) {
        self.completion = completion
        self.previewData = previewData
        self.viewModel = viewModel
        self.onSelectGarment = onSelectGarment
    }

    public var body: some View {
        ZStack {
            Image("appBG", bundle: .module)
                .resizable()
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                ZStack(alignment: .top) {
                    VStack(spacing: Spacing.lg) {
                        HistoryPolaroidCardView(
                            completion: completion,
                            previewData: previewData
                        )
                        .padding(.horizontal, Spacing.lg)
                        .padding(.top, Spacing.lg)
                        .zIndex(2)
                        .frame(width: 345, height: 614)

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
        ZStack(alignment: .top) {
            Image("TornReceipt", bundle: .module)
                .resizable()

            VStack(alignment: .leading, spacing: 16) {
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

                wearSection
            }
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
                        Button {
                            onSelectGarment(entry.item.id)
                        } label: {
                            garmentView(item: entry.item, wearCount: entry.wearCount)
                        }
                        .buttonStyle(.plain)
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
            Text("wardrobe.wearCount.used \(wearCount)", bundle: .module)
                .font(.subheadline)
                .bold()
                .foregroundColor(.black)
        }
    }

    private func label(_ key: LocalizedStringKey) -> Text {
        Text(key, bundle: .module).bold() + Text(verbatim: " :").bold()
    }
}
