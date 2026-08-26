import DesignSystem
import SwiftUI

struct ConflictsBannerView: View {
    let count: Int
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                Text(text)
                    .font(.caption)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .padding(Spacing.md)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.sm)
        .accessibilityLabel(text)
        .accessibilityHint(Text("conflicts.banner.hint", bundle: .module))
    }

    private var text: String {
        String(format: String(localized: "conflicts.banner", bundle: .module), count)
    }
}
