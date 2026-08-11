import DesignSystem
import SwiftUI

/// Shared rendering for text overlays — used by the canvas, the composer
/// preview, and the export composition so all three stay WYSIWYG.
struct TextItemLabel: View {
    let item: TextItem
    let fontSize: CGFloat

    var body: some View {
        Text(item.content)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(item.hasBackground ? item.textColor.contrastText : item.textColor.color)
            .padding(item.hasBackground ? EdgeInsets(
                top: fontSize * 0.15, leading: fontSize * 0.35,
                bottom: fontSize * 0.15, trailing: fontSize * 0.35
            ) : EdgeInsets())
            .background {
                if item.hasBackground {
                    Capsule().fill(item.textColor.color)
                }
            }
            .shadow(
                color: AppColor.mediaBackground.opacity(item.hasBackground ? 0 : 0.4),
                radius: fontSize * 0.05
            )
    }
}

/// Shared rendering for emoji stickers.
struct StickerLabel: View {
    let item: StickerItem
    let fontSize: CGFloat

    var body: some View {
        Text(verbatim: item.emoji)
            .font(.system(size: fontSize))
    }
}
