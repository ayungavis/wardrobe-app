import DesignSystem
import SwiftUI

struct DevDiagnosticsSectionView: View {
    let entries: [DiagnosticEntry]
    let onClear: () -> Void

    var body: some View {
        Section {
            if entries.isEmpty {
                Text(verbatim: "No errors recorded")
            }

            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(verbatim: entry.message).font(.caption)
                    Text(verbatim: Self.detail(entry)).font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Button(role: .destructive, action: onClear) { Text(verbatim: "Clear errors") }
                .disabled(entries.isEmpty)
        } header: {
            Text(verbatim: "Diagnostics")
        }
    }

    private static func detail(_ entry: DiagnosticEntry) -> String {
        var parts = [entry.at.formatted(.dateTime.hour().minute().second())]
        if let operation = entry.operation {
            parts.append(operation)
        }
        if let endpoint = entry.endpoint {
            parts.append(endpoint)
        }
        if let status = entry.status {
            parts.append("→ \(status)")
        }
        if let requestID = entry.requestID {
            parts.append(requestID)
        }
        return parts.joined(separator: " · ")
    }
}
