import DesignSystem
import SwiftUI

struct SnapBadgeView: View {
    let systemName: String
    let value: Text

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: systemName)
            value
                .monospacedDigit()
        }
        .font(AppFont.caption.weight(.bold))
        .foregroundStyle(AppColor.onMedia)
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: 30)
        .background(AppColor.mediaBackground.opacity(0.72), in: .capsule)
        .overlay { Capsule().stroke(AppColor.accent.opacity(0.88), lineWidth: 1) }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
