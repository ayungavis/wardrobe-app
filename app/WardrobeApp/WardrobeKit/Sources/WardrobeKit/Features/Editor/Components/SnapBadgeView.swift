import DesignSystem
import SwiftUI

/// The little capsule that names what a transform just landed on — "45°",
/// "100%".
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
        // Minimum rather than fixed: the prototype pinned this at 30 with a
        // font that grows with Dynamic Type, so the text clipped at large sizes.
        .frame(minHeight: 30)
        .background(AppColor.mediaBackground.opacity(0.72), in: .capsule)
        .overlay { Capsule().stroke(AppColor.accent.opacity(0.88), lineWidth: 1) }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
