import SwiftUI

struct DevMediaSectionView: View {
    let state: Loadable<String>
    let pendingUploads: [MediaUpload]
    let onRoundTrip: () -> Void

    var body: some View {
        Section {
            LabeledContent {
                Text(verbatim: Self.detail(state)).font(.caption.monospaced())
            } label: {
                Text(verbatim: "Round trip")
            }

            LabeledContent {
                Text(verbatim: Self.queueSummary(pendingUploads)).font(.caption.monospaced())
            } label: {
                Text(verbatim: "Upload queue")
            }

            Button(action: onRoundTrip) { Text(verbatim: "Media round trip") }
        } header: {
            Text(verbatim: "Media")
        }
    }

    private static func queueSummary(_ uploads: [MediaUpload]) -> String {
        guard !uploads.isEmpty else { return "empty" }
        let failed = uploads.count { $0.state == .failed }
        return "\(uploads.count) queued, \(failed) failed"
    }

    private static func detail(_ state: Loadable<String>) -> String {
        switch state {
        case .idle: "never"
        case .loading: "uploading…"
        case let .loaded(summary): summary
        case let .failed(error): "FAILED — \(error)"
        }
    }
}
