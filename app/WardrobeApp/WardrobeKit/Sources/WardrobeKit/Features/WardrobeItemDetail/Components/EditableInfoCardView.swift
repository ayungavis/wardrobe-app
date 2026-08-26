import DesignSystem
import SwiftUI

struct EditableInfoCardView: View {
    let isEditing: Bool
    @Binding var name: String
    @Binding var description: String
    let lastWornAt: Date?
    let wears: [WearRecord]

    @State private var isWearHistoryPresented = false

    var body: some View {
        ZStack(alignment: .top) {
            Image("ShortPaper", bundle: .module)
                .resizable()

            VStack(alignment: .leading, spacing: Spacing.lg) {
                HStack {
                    label("wardrobe.detail.name")
                    if isEditing {
                        TextField(String(localized: "wardrobe.detail.name", bundle: .module), text: $name)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                            .onSubmit {}
                    } else {
                        Text(name)
                    }
                }

                Divider()

                HStack {
                    label("wardrobe.detail.lastWorn")
                    Text(lastWornText(lastWornAt))
                    Spacer()

                    Button {
                        isWearHistoryPresented = true
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $isWearHistoryPresented) {
                        WearHistoryPopoverView(wears: wears)
                            .presentationCompactAdaptation(.popover)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    label("wardrobe.detail.description")
                    if isEditing {
                        TextEditor(text: $description)
                            .frame(minHeight: 60)
                            .padding(Spacing.xs)
                            .scrollContentBackground(.hidden)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    } else {
                        Text(description.isEmpty ? " " : description)
                            .frame(minHeight: 60, alignment: .topLeading)
                    }
                }
            }
            .font(AppFont.body)
            .foregroundColor(.black)
            .padding(.top, 40)
            .padding(.horizontal, Spacing.xxl)
            .padding(.bottom, 40)
        }
    }

    private func label(_ key: LocalizedStringKey) -> Text {
        Text(key, bundle: .module).bold() + Text(verbatim: " :").bold()
    }

    private func lastWornText(_ date: Date?) -> String {
        guard let date else { return String(localized: "wardrobe.detail.never", bundle: .module) }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
