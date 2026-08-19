import DesignSystem
import SwiftUI

struct DeleteDropTargetView: View {
    let isActive: Bool

    var body: some View {
        Image(systemName: "trash")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(AppColor.onMedia)
            .frame(width: 56, height: 56)
            .background {
                Circle()
                    .fill(AppColor.destructive)
                    .opacity(isActive ? 1 : 0)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .scaleEffect(isActive ? 1.18 : 1)
            .padding(.bottom, Spacing.lg)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
