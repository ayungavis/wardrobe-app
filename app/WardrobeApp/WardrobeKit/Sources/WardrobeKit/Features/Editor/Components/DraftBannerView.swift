import DesignSystem
import SwiftUI

struct DraftBannerView: View {
    enum Kind {
        case restored
        case writeFailed
    }

    let kind: Kind

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: kind == .restored ? "clock.arrow.circlepath" : "exclamationmark.triangle.fill")
                .foregroundStyle(kind == .restored ? AppColor.onMedia : AppColor.warning)

            Text(kind == .restored ? "editor.draft.restored" : "editor.draft.failed", bundle: .module)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.onMedia)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("editor.draft.banner")
    }
}
