import DesignSystem
import SwiftUI

struct ChallengeCardStickyView: View {
    let card: ChallengeCard
    let placement: StickerPlacement
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            Image(placement.imageName, bundle: .module)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: width * placement.widthFraction)

            VStack(spacing: Spacing.xs) {
                if let title = card.title {
                    Text(title)
                        .font(AppFont.body)
                        .multilineTextAlignment(.center)
                }
                Text(card.prompt)
                    .font(AppFont.body)
                    .multilineTextAlignment(.center)
            }
            .frame(width: width * placement.widthFraction * 0.8)
        }
        .position(x: width * placement.x, y: height * placement.y)
    }
}
