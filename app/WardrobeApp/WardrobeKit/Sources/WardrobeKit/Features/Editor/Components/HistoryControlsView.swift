import DesignSystem
import SwiftUI

struct HistoryControlsView: View {
    let canUndo: Bool
    let canRedo: Bool
    let onUndo: () -> Void
    let onRedo: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            button(
                systemName: "arrow.uturn.backward",
                label: "editor.undo",
                hint: "editor.undo.hint",
                isEnabled: canUndo,
                action: onUndo
            )
            .accessibilityIdentifier("editor.undo")

            Divider()
                .overlay(AppColor.onMedia.opacity(0.16))
                .frame(height: 20)

            button(
                systemName: "arrow.uturn.forward",
                label: "editor.redo",
                hint: "editor.redo.hint",
                isEnabled: canRedo,
                action: onRedo
            )
            .accessibilityIdentifier("editor.redo")
        }
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
    }

    private func button(
        systemName: String,
        label: LocalizedStringKey,
        hint: LocalizedStringKey,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            EditorHaptics.selection.play()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColor.onMedia)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        // FR-088: with no step left the control is disabled rather than a
        // press that quietly does nothing.
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.36)
        .accessibilityLabel(Text(label, bundle: .module))
        .accessibilityHint(Text(hint, bundle: .module))
    }
}
