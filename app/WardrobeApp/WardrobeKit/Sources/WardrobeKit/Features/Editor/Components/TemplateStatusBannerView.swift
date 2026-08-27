import DesignSystem
import SwiftUI

struct TemplateStatusBannerView: View {
    let state: Loadable<Bool>
    let stillWorking: Bool
    let onCancel: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            switch state {
            case .idle, .loading:
                ProgressView()
                    .controlSize(.small)
                Text("editor.template.working", bundle: .module)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.onMedia)
                Button(action: onCancel) {
                    Text("common.cancel", bundle: .module)
                        .font(AppFont.caption.bold())
                }
            case let .failed(error):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppColor.warning)
                Text(stillWorking
                    ? String(localized: "editor.template.stillWorking", bundle: .module)
                    : error.userMessage)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.onMedia)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onRetry) {
                    Text("common.retry", bundle: .module)
                        .font(AppFont.caption.bold())
                }
            case .loaded:
                EmptyView()
            }
        }
        .tint(AppColor.onMedia)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor.template.banner")
    }
}
