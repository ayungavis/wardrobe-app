import DesignSystem
import SwiftUI

/// Every layer operation §19 requires, as buttons.
///
/// "No operation may require drag, pinch, or rotation gestures as its only
/// path" — so reordering, moving, resizing, and rotating all have an entry
/// here, and the adjustments nest one level down to keep the top level
/// readable.
struct LayerMenuView: View {
    let isLocked: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMove: (EditorDocument.LayerMove) -> Void
    let onStep: (LayerStep) -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Menu {
            Section {
                button("editor.layer.toFront", "square.3.layers.3d.top.filled") { onMove(.front) }
                    .disabled(!canMoveUp)
                button("editor.layer.forward", "chevron.up") { onMove(.forward) }
                    .disabled(!canMoveUp)
                button("editor.layer.backward", "chevron.down") { onMove(.backward) }
                    .disabled(!canMoveDown)
                button("editor.layer.toBack", "square.3.layers.3d.bottom.filled") { onMove(.back) }
                    .disabled(!canMoveDown)
            }

            Menu {
                adjustments
            } label: {
                Label {
                    Text("editor.layer.adjust", bundle: .module)
                } icon: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
            // FR-086: a locked layer keeps its geometry, so the controls that
            // would change it are closed rather than silently ignored.
            .disabled(isLocked)

            Section {
                button("editor.layer.duplicate", "plus.square.on.square", haptic: .commit, action: onDuplicate)

                Button(role: .destructive) {
                    EditorHaptics.removed.play()
                    onDelete()
                } label: {
                    Label {
                        Text("editor.layer.delete", bundle: .module)
                    } icon: {
                        Image(systemName: "trash")
                    }
                }
                // FR-087: deleting a locked layer takes an explicit unlock
                // first. A live button that did nothing would be worse.
                .disabled(isLocked)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AppColor.onMedia)
                .frame(width: 44, height: 44)
                .background(AppColor.onMedia.opacity(0.08), in: Circle())
        }
        .accessibilityIdentifier("editor.layer.actions")
    }

    @ViewBuilder
    private var adjustments: some View {
        Section {
            button("editor.layer.moveLeft", "arrow.left") { onStep(.left) }
            button("editor.layer.moveRight", "arrow.right") { onStep(.right) }
            button("editor.layer.moveUp", "arrow.up") { onStep(.up) }
            button("editor.layer.moveDown", "arrow.down") { onStep(.down) }
        }

        Section {
            button("editor.layer.bigger", "plus.magnifyingglass") { onStep(.bigger) }
            button("editor.layer.smaller", "minus.magnifyingglass") { onStep(.smaller) }
            button("editor.layer.rotateLeft", "rotate.left") { onStep(.rotateLeft) }
            button("editor.layer.rotateRight", "rotate.right") { onStep(.rotateRight) }
        }

        Section {
            button("editor.layer.reset", "arrow.counterclockwise") { onStep(.reset) }
        }
    }

    private func button(
        _ key: LocalizedStringKey,
        _ systemName: String,
        haptic: EditorHaptics = .selection,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            haptic.play()
            action()
        } label: {
            Label {
                Text(key, bundle: .module)
            } icon: {
                Image(systemName: systemName)
            }
        }
    }
}
