import DesignSystem
import SwiftUI

/// The AI's proposal about what the user is wearing, as a collapsible drawer
/// over the editor (PRD FR-027).
///
/// Collapsed by default: the photo is what the user came here for, and the
/// wardrobe bookkeeping must never be in the way of finishing the challenge.
struct ItemReviewDrawerView: View {
    let garments: [ScannedGarment]
    let isScanning: Bool
    let thumbnail: (String) -> Data?
    let itemThumbnail: (UUID) -> Data?
    let onChoose: (UUID, ScannedGarment.Decision) -> Void

    @State private var isExpanded = false

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
        VStack(alignment: .leading, spacing: Spacing.md) {
            ForEach(garments) { garment in
                ScannedGarmentRowView(
                    garment: garment,
                    scannedImage: thumbnail(garment.cutoutFile),
                    candidateImage: itemThumbnail
                ) { decision in
                    onChoose(garment.id, decision)
                }
            }
        }
        .padding(Spacing.md)
        // ponytail: fixed ceiling instead of a measured one — two garments per
        // photo is the norm, and the drawer must never swallow the canvas.
        .frame(maxHeight: 320)
    }
}
