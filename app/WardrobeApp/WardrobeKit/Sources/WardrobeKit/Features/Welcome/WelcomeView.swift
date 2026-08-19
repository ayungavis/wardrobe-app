import DesignSystem
import SwiftUI

public struct WelcomeView: View {
    private let onContinue: () -> Void

    public init(onContinue: @escaping () -> Void) {
        self.onContinue = onContinue
    }

    public var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            Image(systemName: "tshirt.fill")
                .font(.system(size: 64))
                .foregroundStyle(AppColor.accent)

            Text("welcome.title", bundle: .module)
                .font(AppFont.largeTitle)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)

            Text("welcome.subtitle", bundle: .module)
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)

            Spacer()

            PrimaryButtonView(Text("welcome.continue", bundle: .module), action: onContinue)
        }
        .padding(Spacing.xl)
    }
}

#Preview {
    WelcomeView {}
}
