import DesignSystem
import SwiftUI

struct RegenerateIllustrationView: View {
    let cutout: Data?
    let original: Data?
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note = ""

    private var references: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            reference(cutout, caption: "wardrobe.detail.regenerate.cutout")
            reference(original, caption: "wardrobe.detail.regenerate.original")
        }
    }

    private func reference(_ data: Data?, caption: LocalizedStringKey) -> some View {
        VStack(spacing: Spacing.xs) {
            Group {
                if let data {
                    DownsampledPhotoView(data: data, maxPixel: 600)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppColor.surface)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(AppColor.textSecondary)
                        }
                }
            }
            .frame(height: 140)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(caption, bundle: .module)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                references

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
