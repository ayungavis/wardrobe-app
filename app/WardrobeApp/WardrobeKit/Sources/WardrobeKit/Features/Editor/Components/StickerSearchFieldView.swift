import DesignSystem
import SwiftUI

struct StickerSearchFieldView: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColor.onMedia.opacity(0.64))

            TextField(text: $query) {
                Text("editor.sticker.search", bundle: .module)
            }
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            #if os(iOS)
                .textInputAutocapitalization(.never)
            #endif
                .accessibilityIdentifier("editor.sticker.search")

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppColor.onMedia.opacity(0.64))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("common.clear", bundle: .module))
            }
        }
        .font(.system(size: 15))
        .padding(.horizontal, Spacing.md)
        .frame(height: 38)
        .background(AppColor.onMedia.opacity(0.10), in: .capsule)
    }
}
