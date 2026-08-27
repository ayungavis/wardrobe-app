import DesignSystem
import SwiftUI

struct ShareQRSheetView: View {
    let state: Loadable<CompletionShare>
    let onRetry: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .idle, .loading:
                    ProgressView()
                case let .failed(error):
                    ContentUnavailableView {
                        Label {
                            Text("common.errorTitle", bundle: .module)
                        } icon: {
                            Image(systemName: "qrcode.viewfinder")
                        }
                    } description: {
                        Text(error.userMessage)
                    } actions: {
                        Button(action: onRetry) { Text("common.retry", bundle: .module) }
                    }
                case let .loaded(share):
                    loaded(share)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(Text("history.share.title", bundle: .module))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .presentationDetents([.medium, .large])
    }

    private func loaded(_ share: CompletionShare) -> some View {
        VStack(spacing: Spacing.xl) {
            Image(decorative: share.qr, scale: 1)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 260)
                .padding(Spacing.lg)
                .background(Color.white)
                .clipShape(.rect(cornerRadius: 12))

            VStack(spacing: Spacing.sm) {
                Text("history.share.hint", bundle: .module)
                    .font(AppFont.body)
                Text("history.share.expires", bundle: .module)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            .multilineTextAlignment(.center)
        }
        .padding(Spacing.xl)
    }
}
