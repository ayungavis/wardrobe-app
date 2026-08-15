import DesignSystem
import SwiftUI

struct ChallengeCardView: View {
    let card: ChallengeCard
    let onAccept: () -> Void
    
    var body: some View {
        ZStack {
            Image("ChallengeSheet", bundle: .module)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 346, height: 617)
            
            VStack(spacing: Spacing.xl) {
                VStack {
                    HStack {
                        Spacer()
                        Text("Today's")
                            
                    }
                    Text("Challenge")
                        .font(AppFont.title)
                }
                //Spacer()
                ZStack {
                    Image("Sticky", bundle: .module)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                    VStack {
                        Text("Prompt Title")
                        Spacer()
                        Text(card.prompt)
                    }
                    .padding(Spacing.xl)
                }
                .frame(width: 260, height: 125)
//                Text(card.prompt)
//                    .font(AppFont.title)
//                    .foregroundStyle(AppColor.textPrimary)
//                    .multilineTextAlignment(.center)
                
                PrimaryButtonView(Text("challenge.accept", bundle: .module), action: onAccept)
            }
            .padding(Spacing.xl)
            .frame(width: 346, height: 600)
            
            //.background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16))
            .appShadow(.card)
        }
        //.foregroundStyle(AppColor.textPrimary)
    }
}

#Preview {
    ChallengeCardView(
        card: ChallengeCard(id: UUID(), prompt: "Wear something you haven't worn in a month"),
        onAccept: {}
    )
}
