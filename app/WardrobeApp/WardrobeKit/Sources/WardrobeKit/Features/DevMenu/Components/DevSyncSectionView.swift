import SwiftUI

struct DevSyncSectionView: View {
    let cursor: Int64
    let state: Loadable<PullOutcome>
    let reconcile: Loadable<ReconcileOutcome>
    let onPull: () -> Void
    let onReconcile: () -> Void

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

            LabeledContent {
                Text(verbatim: Self.summary(reconcile)).font(.caption.monospaced())
            } label: {
                Text(verbatim: "Last reconcile")
            }

            Button(action: onReconcile) { Text(verbatim: "Reconcile now") }
            Button(action: onPull) { Text(verbatim: "Pull GET /v1/changes") }
        } header: {
            Text(verbatim: "Sync")
        }
    }

    private static func summary(_ state: Loadable<ReconcileOutcome>) -> String {
        switch state {
        case .idle: "never"
        case .loading: "reconciling…"
        case let .loaded(outcome):
            "sent \(outcome.pushed), rejected \(outcome.rejected), pulled \(outcome.pulled)"
        case let .failed(error): "FAILED — \(error)"
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
