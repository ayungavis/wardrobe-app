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
    /// Measured height of the rows, so the drawer can hug short content and
    /// stop growing at the ceiling.
    @State private var contentHeight: CGFloat = 0

    /// The drawer must never swallow the canvas the user came here for.
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

    /// Grows with the number of detected garments, up to a ceiling, and scrolls
    /// beyond it.
    ///
    /// The height is measured rather than merely capped: a `ScrollView` is
    /// greedy along its scroll axis, so bounding it would make the drawer that
    /// tall even for a single garment. What is measured is the *content* — its
    /// intrinsic height depends only on the available width, never on the height
    /// handed to the scroll view, so the layout converges instead of oscillating.
    private var rows: some View {
        ScrollView {
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
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .frame(height: min(contentHeight, Self.maxRowsHeight))
        // Rubber-banding on a drawer that is not scrolling would suggest there
        // is more to see when there is not.
        .scrollDisabled(contentHeight <= Self.maxRowsHeight)
    }
}
