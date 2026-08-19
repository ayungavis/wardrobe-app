import DesignSystem
import SwiftUI

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

    private var padding: EdgeInsets {
        guard item.backgroundStyle != .none else { return EdgeInsets() }
        return EdgeInsets(
            top: fontSize * 0.15, leading: fontSize * 0.35,
            bottom: fontSize * 0.15, trailing: fontSize * 0.35
        )
    }

    private var shadowColor: Color {
        AppColor.mediaBackground.opacity(item.backgroundStyle == .none ? 0.4 : 0)
    }
}
