import DesignSystem
import SwiftUI

public struct HistoryDetailView: View {
    public let completion: CompletedChallenge
    public let previewData: Data?
    @Bindable var viewModel: HistoryViewModel

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
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .appBackgroundOnly()
        .task { garments = viewModel.garmentsWorn(in: completion) }
        .navigationTitle(Text("tab.history", bundle: .module))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar { toolbar }
            .sheet(isPresented: $viewModel.isSharePresented) {
                ShareQRSheetView(state: viewModel.share) { viewModel.share(completion) }
            }
            .alert(
                Text("common.errorTitle", bundle: .module),
                isPresented: Binding(
                    get: { viewModel.alertError != nil },
                    set: {
                        if !$0 {
                            viewModel.alertError = nil
                        }
                    }
                )
            ) {
                Button(role: .cancel) {} label: { Text("common.ok", bundle: .module) }
            } message: {
                Text(viewModel.alertError?.userMessage ?? "")
            }
            .alert(
                Text("history.detail.saved", bundle: .module),
                isPresented: Binding(
                    get: { viewModel.didSave },
                    set: {
                        if !$0 {
                            viewModel.acknowledgeSave()
                        }
                    }
                )
            ) {
                Button(role: .cancel) {} label: { Text("common.ok", bundle: .module) }
            }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button {
                viewModel.share(completion)
            } label: {
                Image(systemName: "qrcode")
            }
            .accessibilityLabel(Text("history.detail.share", bundle: .module))
        }
        ToolbarItem(placement: .confirmationAction) {
            Button {
                viewModel.save(completion)
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .accessibilityLabel(Text("history.detail.save", bundle: .module))
        }
    }

    private var receiptContent: some View {
        ZStack(alignment: .top) {
            Image("TornReceipt", bundle: .module)
                .resizable()

            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(alignment: .top) {
                        label("history.detail.date")
                        Text(completion.completedAt, format: .dateTime.day().month(.wide).year())
                    }

                    if completion.documentState != .available {
                        Text(
                            completion.documentState == .pending
                                ? "history.detail.document.pending"
                                : "history.detail.document.unsupported",
                            bundle: .module
                        )
                        .font(AppFont.caption)
                        .foregroundColor(AppColor.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        label("history.detail.description")
                        Text(completion.card.prompt)
                            .font(AppFont.body)
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
        VStack(alignment: .leading, spacing: Spacing.md) {
            label("history.detail.wear")

            if garments.isEmpty {
                Text("history.detail.garments.empty", bundle: .module)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            } else {
                HStack(spacing: Spacing.lg) {
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
        .padding(.bottom, Spacing.xl)
    }

    private func garmentView(item: WardrobeItem, wearCount: Int) -> some View {
        VStack(spacing: Spacing.sm) {
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
