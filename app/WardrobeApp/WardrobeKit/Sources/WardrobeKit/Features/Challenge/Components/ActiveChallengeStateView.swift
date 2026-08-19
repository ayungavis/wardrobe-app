import DesignSystem
import SwiftUI

struct ActiveChallengeStateView: View {
    let challenge: ActiveChallenge
    let onResume: () -> Void
    let onAbandon: () -> Void

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            Text("challenge.active.title", bundle: .module)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .textCase(.uppercase)

            Text(challenge.card.prompt)
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)

            Spacer()

            PrimaryButtonView(Text("challenge.active.resume", bundle: .module), action: onResume)

            Button(role: .destructive, action: onAbandon) {
                Text("challenge.active.abandon", bundle: .module)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(Spacing.xl)
    }
}

#Preview {
    let container = AppContainer()
    ChallengeView(viewModel: container.makeChallengeViewModel(), container: container)
}
