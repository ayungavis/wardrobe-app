import CoreGraphics
import DesignSystem
import SwiftUI

struct LayerRowView: View {
    let layer: EditorLayer
    let photo: (String) -> CGImage?
    let isSelected: Bool
    let depth: Int
    let layerCount: Int
    let isReordering: Bool
    let isChallengePhoto: Bool
    let onSelect: () -> Void
    let onToggleLock: () -> Void
    let onMove: (EditorDocument.LayerMove) -> Void
    let onStep: (LayerStep) -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            selectButton

            if !isReordering {
                lockButton
                LayerMenuView(
                    isLocked: layer.isLocked,
                    canDelete: !isChallengePhoto,
                    canMoveUp: depth < layerCount - 1,
                    canMoveDown: depth > 0,
                    onMove: onMove,
                    onStep: onStep,
                    onDuplicate: onDuplicate,
                    onDelete: onDelete
                )
                .accessibilityLabel(Text("editor.layer.actions", bundle: .module))
            }
        }
        .padding(.vertical, Spacing.xs)
        .listRowBackground(isSelected ? AppColor.accent.opacity(0.14) : AppColor.onMedia.opacity(0.04))
        .listRowSeparator(.hidden)
    }

    private var selectButton: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.md) {
                LayerThumbnailView(content: layer.content, photo: photo)

                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: LayerLabel.title(for: layer.content, isChallengePhoto: isChallengePhoto))
                        .font(AppFont.body.weight(.semibold))
                        .foregroundStyle(AppColor.onMedia)
                        .lineLimit(1)

                    Text(verbatim: LayerLabel.kind(for: layer.content, isChallengePhoto: isChallengePhoto))
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.onMedia.opacity(0.64))
                }

                Spacer(minLength: Spacing.sm)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColor.accent)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: LayerLabel.title(for: layer.content, isChallengePhoto: isChallengePhoto)))
        .accessibilityValue(Text(verbatim: accessibilityValue))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("editor.layer.row")
    }

    private var accessibilityValue: String {
        let order = String(
            localized: "editor.layer.order \(layerCount - depth) \(layerCount)", bundle: .module
        )
        guard layer.isLocked else { return order }
        return "\(order), \(LocalizedKey.resolve("editor.layer.locked"))"
    }

    private var lockButton: some View {
        Button {
            (layer.isLocked ? EditorHaptics.selection : .locked).play()
            onToggleLock()
        } label: {
            Image(systemName: layer.isLocked ? "lock.fill" : "lock.open")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(layer.isLocked ? AppColor.warning : AppColor.onMedia.opacity(0.64))
                .frame(width: 44, height: 44)
                .background(AppColor.onMedia.opacity(0.08), in: Circle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text(
            layer.isLocked ? "editor.layer.unlock" : "editor.layer.lock", bundle: .module
        ))
        .accessibilityIdentifier("editor.layer.lockToggle")
    }
}
