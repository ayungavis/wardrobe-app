import DesignSystem
import SwiftUI

struct OnboardingStepView: View {
    let step: OnboardingStep

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: step.symbolName)
                .font(.system(size: 72))
                .foregroundStyle(AppColor.accent)

            Text(LocalizedStringKey(step.titleKey), bundle: .module)
                .font(AppFont.largeTitle)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Spacing.xl)
    }
}
