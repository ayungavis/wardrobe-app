import DesignSystem
import SwiftUI

/// Shared rendering for text layers — the canvas, the composer preview, and the
/// export composition all draw through this, so what you arrange is what gets
/// saved and shared.
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
            .foregroundStyle(foregroundStyle)
            .padding(padding)
            .background {
                if item.backgroundStyle != .none {
                    Capsule().fill(backgroundFill)
                }
            }
            .shadow(color: shadowColor, radius: fontSize * 0.05)
    }

    /// On a solid pill the text flips to whatever reads against it; on the dark
    /// pill it keeps its colour, except black, which would vanish.
    private var foregroundStyle: Color {
        switch item.backgroundStyle {
        case .none: item.textColor.color
        case .solid: item.textColor.contrastText
        case .translucent: item.textColor == .black ? .white : item.textColor.color
        }
    }

    private var backgroundFill: Color {
        switch item.backgroundStyle {
        case .none: .clear
        case .solid: item.textColor.color
        case .translucent: AppColor.mediaBackground.opacity(0.52)
        }
    }

    /// Proportional to the font size, so a pill keeps its shape at every scale
    /// and at export size.
    private var padding: EdgeInsets {
        guard item.backgroundStyle != .none else { return EdgeInsets() }
        return EdgeInsets(
            top: fontSize * 0.15, leading: fontSize * 0.35,
            bottom: fontSize * 0.15, trailing: fontSize * 0.35
        )
    }

    /// Only bare text needs lifting off the photo; a pill already separates it.
    private var shadowColor: Color {
        AppColor.mediaBackground.opacity(item.backgroundStyle == .none ? 0.4 : 0)
    }
}
