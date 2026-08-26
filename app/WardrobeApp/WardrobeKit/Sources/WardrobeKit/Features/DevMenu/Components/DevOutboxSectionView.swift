import SwiftUI

struct DevOutboxSectionView: View {
    let entries: [OutboxEnvelope]
    let onRetryFailed: () -> Void
    let onClear: () -> Void

    var body: some View {
        Section {
            LabeledContent {
                Text(verbatim: "\(entries.count) queued, \(failedCount) failed")
                    .font(.caption.monospaced())
            } label: {
                Text(verbatim: "Outbox")
            }

            ForEach(entries) { entry in
                LabeledContent {
                    Text(verbatim: Self.detail(entry)).font(.caption.monospaced())
                } label: {
                    Text(verbatim: entry.name)
                }
            }

            Button(action: onRetryFailed) { Text(verbatim: "Retry failed") }
                .disabled(failedCount == 0)
            Button(role: .destructive, action: onClear) { Text(verbatim: "Clear outbox") }
                .disabled(entries.isEmpty)
        } header: {
            Text(verbatim: "Outbox")
        }
    }

    private var failedCount: Int {
        entries.count { $0.state == .failed }
    }

    private static func detail(_ entry: OutboxEnvelope) -> String {
        let next = entry.nextAttemptAt.formatted(.dateTime.hour().minute().second())
        let code = entry.lastErrorCode.map { " · \($0)" } ?? ""
        return "\(entry.state.rawValue) · try \(entry.attempts) · next \(next)\(code)"
    }
}
