import SwiftUI

/// Shared rendering for emoji stickers.
struct StickerLabelView: View {
    let emoji: String
    let fontSize: CGFloat

    var body: some View {
        Text(verbatim: emoji)
            .font(.system(size: fontSize))
    }
}
