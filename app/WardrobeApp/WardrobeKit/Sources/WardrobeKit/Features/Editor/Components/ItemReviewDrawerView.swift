import DesignSystem
import SwiftUI

struct ItemReviewDrawerView: View {
    let garments: [ScannedGarment]
    let isScanning: Bool
    let thumbnail: (String) -> Data?
    let itemThumbnail: (UUID) -> Data?
    let onChoose: (UUID, ScannedGarment.Decision) -> Void

    @State private var isExpanded = false
    @State private var contentHeight: CGFloat = 0

    private static let maxRowsHeight: CGFloat = 320

    var body: some View {
        if isScanning || !garments.isEmpty {
            VStack(spacing: 0) {
                handle
                if isExpanded {
                    rows
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .environment(\.colorScheme, .dark)
            .padding(.horizontal, Spacing.lg)
        }
    }

    private var handle: some View {
        Button {
            withAnimation(.snappy) { isExpanded.toggle() }
        } label: {
            HStack(spacing: Spacing.sm) {
                if isScanning {
                    ProgressView().tint(AppColor.onMedia)
                    Text("editor.review.scanning", bundle: .module)
                } else {
                    Image(systemName: "tshirt")
                    Text("editor.review.detected \(garments.count)", bundle: .module)
                }
                Spacer()
                if !isScanning {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                }
            }
            .font(AppFont.caption)
            .foregroundStyle(AppColor.onMedia)
            .padding(Spacing.md)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isScanning)
    }

    private var rows: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(garments) { garment in
                    ScannedGarmentRowView(
                        garment: garment,
                        scannedImage: thumbnail(garment.cutoutFile),
                        candidateImage: itemThumbnail,
                        allowsMatching: true

                    ) { decision in
                        onChoose(garment.id, decision)
                    }
                }
            }
            .padding(Spacing.md)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .frame(height: min(contentHeight, Self.maxRowsHeight))
        .scrollDisabled(contentHeight <= Self.maxRowsHeight)
    }
}
