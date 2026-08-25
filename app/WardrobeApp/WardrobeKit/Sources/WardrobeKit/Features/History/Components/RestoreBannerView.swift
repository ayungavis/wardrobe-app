import DesignSystem
import SwiftUI

struct RestoreBannerView: View {
    let remaining: Int
    let failed: Int
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ProgressView()
            Text(text)
                .font(.caption)
            Spacer()
            if failed > 0 {
                Button(action: onRetry) {
                    Text("history.restore.retry", bundle: .module)
                        .font(.caption.bold())
                }
            }
        }
        .padding(Spacing.md)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }

    private var text: String {
        if failed > 0 {
            String(format: String(localized: "history.restore.failed", bundle: .module), failed)
        } else {
            String(format: String(localized: "history.restore.remaining", bundle: .module), remaining)
        }
    }
}
