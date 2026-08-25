import DesignSystem
import SwiftUI

struct WardrobeSyncBannerView: View {
    let pending: Int
    let failed: Int
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(text)
                .font(.caption)
            Spacer()
            if failed > 0 {
                Button(action: onRetry) {
                    Text("wardrobe.sync.retry", bundle: .module)
                        .font(.caption.bold())
                }
            }
        }
        .padding(Spacing.md)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.sm)
    }

    private var text: String {
        if failed > 0 {
            String(format: String(localized: "wardrobe.sync.failed", bundle: .module), failed)
        } else {
            String(format: String(localized: "wardrobe.sync.pending", bundle: .module), pending)
        }
    }
}
