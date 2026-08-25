import SwiftUI

struct DevMediaSectionView: View {
    let state: Loadable<String>
    let onRoundTrip: () -> Void

    var body: some View {
        Section {
            LabeledContent {
                Text(verbatim: Self.detail(state)).font(.caption.monospaced())
            } label: {
                Text(verbatim: "Round trip")
            }

            Button(action: onRoundTrip) { Text(verbatim: "Media round trip") }
        } header: {
            Text(verbatim: "Media")
        }
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
