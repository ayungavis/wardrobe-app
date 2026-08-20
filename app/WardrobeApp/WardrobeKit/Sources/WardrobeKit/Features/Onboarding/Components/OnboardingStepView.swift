import DesignSystem
import SwiftUI

struct OnboardingStepView<Actions: View>: View {
    let step: OnboardingStep
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: Spacing.md) {
            if step != .firstChallenge {
                Image(step.image, bundle: .module)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 283, height: 486)
            }else{
                Text("onboarding.firstChallenge.cta", bundle: .module)
                    .font(AppFont.largeTitle)
                Image(step.image, bundle: .module)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 353.17, height: 318.57)
            }
            
            
            ZStack() {
                Image("ShortPaper", bundle: .module)
                    .resizable()
                    .scaledToFill()
                VStack(alignment: .leading){
                    Spacer()
                    Text(LocalizedStringKey(step.titleKey), bundle: .module)
                        .font(AppFont.body)
                        .fontWeight(.bold)
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.leading)
                    if step != .firstChallenge {
                        Divider()
                        
                        Text(LocalizedStringKey(step.descKey), bundle: .module)
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.textPrimary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    actions()
                }
                .padding(Spacing.xxl)
            }
            .frame(width: 345, height: 220)
            
        }
        .padding(.horizontal, Spacing.xl)
    }
}
