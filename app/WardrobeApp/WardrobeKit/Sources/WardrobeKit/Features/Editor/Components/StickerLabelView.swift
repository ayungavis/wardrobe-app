import SwiftUI

/// Shared rendering for emoji stickers.
struct StickerLabelView: View {
    let item: StickerItem
    let fontSize: CGFloat

    var body: some View {
        Text(verbatim: item.emoji)
            .font(.system(size: fontSize))
    }
}
