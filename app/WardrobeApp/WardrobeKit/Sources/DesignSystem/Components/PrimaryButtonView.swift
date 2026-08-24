import SwiftUI

public struct PrimaryButtonView: View {
    private let title: Text
    private let action: () -> Void
    private let minHeight: CGFloat

    public init(_ title: Text, minHeight: CGFloat = 44, action: @escaping () -> Void) {
        self.title = title
        self.minHeight = minHeight
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            title
                .font(AppFont.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: minHeight)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppColor.accent)
    }
}

#Preview {
    PrimaryButtonView(Text(verbatim: "Continue")) {}
        .padding()
}
