import CoreGraphics
import DesignSystem
import SwiftUI

struct CapturedStackView: View {
    let thumbnails: [CGImage]
    let count: Int
    let action: () -> Void

    private let side: CGFloat = 56

    var body: some View {
        Group {
            if count > 0 {
                Button(action: action) { stack }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("bulkScan.captured \(count)", bundle: .module))
            }
        }
        .frame(width: side, height: side)
    }

    private var stack: some View {
        ZStack {
            ForEach(Array(thumbnails.enumerated()), id: \.offset) { index, image in
                layer(depth: thumbnails.count - 1 - index) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }

            if thumbnails.isEmpty {
                layer(depth: 0) { Color.clear.background(.ultraThinMaterial) }
            }
        }
        .overlay(alignment: .topTrailing) { badge }
    }

    private func layer(depth: Int, @ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AppColor.onMedia.opacity(0.9), lineWidth: 2)
            }
            .rotationEffect(.degrees(Double(depth) * -4))
            .offset(x: CGFloat(depth) * -2, y: CGFloat(depth) * -2)
    }

    private var badge: some View {
        Text(count, format: .number)
            .font(AppFont.roundedCaption)
            .foregroundStyle(AppColor.onMedia)
            .padding(Spacing.xs)
            .frame(minWidth: 22, minHeight: 22)
            .background(Circle().fill(AppColor.accent))
            .offset(x: Spacing.sm, y: -Spacing.sm)
    }
}
