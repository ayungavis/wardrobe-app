import DesignSystem
import SwiftUI

/// Shared rendering for text overlays — used by the canvas, the composer
/// preview, and the export composition so all three stay WYSIWYG.
///
/// Takes the layer's content rather than a whole `TextItem`: placement belongs
/// to whoever positions the view, and passing it here would let the two
/// disagree.
struct TextItemLabelView: View {
    let item: TextContent
    let fontSize: CGFloat

    var body: some View {
        Text(item.content)
            .font(.system(size: fontSize, weight: item.fontStyle.weight, design: item.fontStyle.design))
            .multilineTextAlignment(item.alignmentStyle.textAlignment)
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
