import DesignSystem
import SwiftUI

struct ItemConflictRowView: View {
    let display: ConflictsViewModel.ItemConflictDisplay
    let onKeepCurrent: () -> Void
    let onUseIncoming: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(.headline)
            valueRow(
                label: Text("conflicts.item.current", bundle: .module),
                value: display.currentValue
            )
            valueRow(
                label: Text("conflicts.item.incoming", bundle: .module),
                value: display.conflict.value
            )
            HStack(spacing: Spacing.md) {
                Button(action: onKeepCurrent) {
                    Text("conflicts.item.keepCurrent", bundle: .module)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button(action: onUseIncoming) {
                    Text("conflicts.item.useIncoming", bundle: .module)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var title: String {
        String(
            format: String(localized: "conflicts.item.title", bundle: .module),
            display.itemName, display.conflict.field.label
        )
    }

    private func valueRow(label: Text, value: String?) -> some View {
        HStack {
            label
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let value {
                Text(value)
            } else {
                Text("conflicts.item.noValue", bundle: .module)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
