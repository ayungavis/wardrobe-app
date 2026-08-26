import DesignSystem
import SwiftUI

struct RegenerateIllustrationView: View {
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text("wardrobe.detail.regenerate.disclaimer", bundle: .module)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("wardrobe.detail.regenerate.note", bundle: .module)
                        .font(AppFont.caption)
                    TextField(
                        String(localized: "wardrobe.detail.regenerate.notePlaceholder", bundle: .module),
                        text: $note,
                        axis: .vertical
                    )
                    .lineLimit(2 ... 4)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("wardrobe.detail.regenerate.note")
                }

                Spacer()
            }
            .padding(Spacing.lg)
            .navigationTitle(Text("wardrobe.detail.regenerate.title", bundle: .module))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Text("common.cancel", bundle: .module)
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            onConfirm(note)
                        } label: {
                            Text("wardrobe.detail.regenerate.action", bundle: .module)
                        }
                    }
                }
        }
    }
}
