import DesignSystem
import SwiftUI

/// The drop zone a layer is dragged onto to delete it (FR-087).
///
/// Purely a signal: it never hit-tests, because what decides deletion is where
/// the *layer* ended up, not where the finger is. Aiming the layer is what the
/// shrinking and fading make legible.
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
