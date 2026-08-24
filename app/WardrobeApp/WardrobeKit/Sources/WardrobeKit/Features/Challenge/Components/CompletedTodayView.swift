import DesignSystem
import SwiftUI

public struct CompletedTodayView: View {
    let onAccept: (ChallengeCard) -> Void

    public var body: some View {
        VStack {
            FreestyleOutfitView(
                titleKey: "challenge.empty.freestyle.title",
                messageKey: "challenge.empty.freestyle.text",
                buttonKey: "challenge.accept",
                onAccept: {
                    onAccept(ChallengeCard.freestyle)
                }
            )
            .aspectRatio(346 / 617, contentMode: .fit)
            .allowsHitTesting(true)

            Text("challenge.empty.text", bundle: .module)
                .font(AppFont.body.weight(.bold))
                .opacity(0.3)
        }
    }
}
