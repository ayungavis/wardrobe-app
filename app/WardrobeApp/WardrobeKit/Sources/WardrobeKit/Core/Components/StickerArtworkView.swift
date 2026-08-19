import CoreGraphics
import DesignSystem
import SwiftUI

/// Draws a sticker at a given size — the picker's grid and the canvas both go
/// through here, so a swatch cannot promise something the canvas will not draw.
///
/// Every dimension is a multiple of `size`, which is what lets the same view
/// serve a 64pt cell and a 1080-point export frame without anything landing
/// proportionally wrong.
struct StickerArtworkView: View {
    let art: StickerArt
    let size: CGFloat

    var body: some View {
        switch art.design {
        case let .emoji(glyph):
            Text(verbatim: glyph)
                .font(.system(size: size * 0.76))
                .frame(width: size, height: size)
                .shadow(color: shadow.opacity(0.18), radius: size * 0.035, y: size * 0.025)
        case let .symbol(name, accent):
            tile(symbol: name, colors: accent.gradientColors)
        case nil:
            // FR-019: an unavailable catalogue asset must not block editing, so
            // the layer stays and says so rather than vanishing.
            tile(symbol: "questionmark", colors: [
                AppColor.onMedia.opacity(0.32), AppColor.onMedia.opacity(0.18),
            ])
        }
    }

    private func tile(symbol: String, colors: [Color]) -> some View {
        let radius = size * 0.29

        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.43, weight: .black))
                    .foregroundStyle(AppColor.onMedia)
                    .shadow(color: shadow.opacity(0.20), radius: size * 0.025, y: size * 0.02)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(AppColor.onMedia.opacity(0.24), lineWidth: 1)
            }
            .shadow(color: shadow.opacity(0.24), radius: size * 0.06, y: size * 0.04)
    }

    private var shadow: Color {
        AppColor.mediaBackground
    }
}
