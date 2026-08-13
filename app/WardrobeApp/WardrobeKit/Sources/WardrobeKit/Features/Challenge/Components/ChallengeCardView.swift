import DesignSystem
import SwiftUI

struct ChallengeCardView: View {
    let card: ChallengeCard
    let onAccept: () -> Void

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Text(card.prompt)
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)

            PrimaryButtonView(Text("challenge.accept", bundle: .module), action: onAccept)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16))
        .appShadow(.card)
    }
}
