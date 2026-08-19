import DesignSystem
import SwiftUI

struct WardrobeSearchBarView: View {
    @Binding var query: String
    @Binding var isActive: Bool
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .resizable()
                .scaledToFill()
                .frame(width: 20, height: 20)

            if isActive {
                TextField(
                    text: $query,
                    prompt: Text("wardrobe.search.prompt", bundle: .module)
                ) {
                    Text("wardrobe.search", bundle: .module)
                }
                .textFieldStyle(.plain)
                .font(AppFont.body)
                .submitLabel(.search)
                .focused($isFocused)
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                    .autocorrectionDisabled()

                Button {
                    close()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppColor.textSecondary)
                }
                .accessibilityLabel(Text("wardrobe.search.clear", bundle: .module))
            }
        }
        .padding(Spacing.md)
        .background(Capsule().fill(.ultraThinMaterial))
        .contentShape(.capsule)
        .onTapGesture { open() }
        .accessibilityElement(children: isActive ? .contain : .ignore)
        .accessibilityLabel(Text("wardrobe.search", bundle: .module))
        .accessibilityAddTraits(isActive ? [] : .isButton)
        .accessibilityAction { open() }
    }

    private func open() {
        guard !isActive else { return }
        isActive = true
        isFocused = true
    }

    private func close() {
        query = ""
        isActive = false
        isFocused = false
    }
}
