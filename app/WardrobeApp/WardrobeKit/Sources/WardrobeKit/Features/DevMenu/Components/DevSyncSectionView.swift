import SwiftUI

struct DevSyncSectionView: View {
    let cursor: Int64
    let state: Loadable<PullOutcome>
    let onPull: () -> Void

    var body: some View {
        Section {
            LabeledContent {
                Text(verbatim: "\(cursor)").font(.caption.monospaced())
            } label: {
                Text(verbatim: "Cursor")
            }
            LabeledContent {
                Text(verbatim: Self.detail(state)).font(.caption.monospaced())
            } label: {
                Text(verbatim: "Last pull")
            }

            Button(action: onPull) { Text(verbatim: "Pull GET /v1/changes") }
        } header: {
            Text(verbatim: "Sync")
        }
    }

    private static func detail(_ state: Loadable<PullOutcome>) -> String {
        switch state {
        case .idle: "never"
        case .loading: "pulling…"
        case let .loaded(outcome):
            "\(outcome.records) records over \(outcome.pages) page\(outcome.pages == 1 ? "" : "s")"
        case let .failed(error): "FAILED — \(error)"
        }
    }
}
