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
                    .scaledToFit()
                    .frame(maxWidth: 283, maxHeight: 486)
            } else {
                Text("onboarding.firstChallenge.cta", bundle: .module)
                    .font(AppFont.largeTitle)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Image(step.image, bundle: .module)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 353.17, maxHeight: 318.57)
            }

            ZStack {
                Image("ShortPaper", bundle: .module)
                    .resizable()
                    .scaledToFill()
                VStack(alignment: .leading) {
                    Spacer()
                    Text(LocalizedStringKey(step.titleKey), bundle: .module)
                        .font(AppFont.body)
                        .fontWeight(.bold)
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let descKey = step.descKey {
                        Divider()

                        Text(LocalizedStringKey(descKey), bundle: .module)
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.textPrimary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    actions()
                }
                .padding(Spacing.xl)
            }
            .frame(width: 345, height: 220)
        }
        .padding(.horizontal, Spacing.xl)
    }
}
