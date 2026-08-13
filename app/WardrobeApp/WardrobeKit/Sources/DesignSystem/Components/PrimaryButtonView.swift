import SwiftUI

/// Full-width primary action button. Takes a `Text` so callers keep control
/// of localization bundles.
public struct PrimaryButtonView: View {
    private let title: Text
    private let action: () -> Void

    public init(_ title: Text, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            title
                .font(AppFont.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppColor.accent)
    }
}

#Preview {
    PrimaryButtonView(Text(verbatim: "Continue")) {}
        .padding()
}
