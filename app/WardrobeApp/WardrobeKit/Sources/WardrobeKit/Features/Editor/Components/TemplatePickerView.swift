import DesignSystem
import SwiftUI

struct TemplatePickerView: View {
    let viewModel: EditorViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    Text("editor.template.hint", bundle: .module)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)

                    ForEach(OutfitTemplate.allCases) { template in
                        card(template)
                    }
                }
                .padding(Spacing.lg)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(Text("editor.template.title", bundle: .module))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: dismiss.callAsFunction) {
                            Text("common.cancel", bundle: .module)
                        }
                    }
                }
        }
        .presentationDetents([.large])
    }

    private func card(_ template: OutfitTemplate) -> some View {
        Button {
            viewModel.chooseTemplate(template)
            dismiss()
        } label: {
            VStack(spacing: Spacing.sm) {
                Image(template.assetName, bundle: .module)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: 12))

                Text(template.title, bundle: .module)
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textPrimary)
            }
        }
        .buttonStyle(.plain)
    }
}
