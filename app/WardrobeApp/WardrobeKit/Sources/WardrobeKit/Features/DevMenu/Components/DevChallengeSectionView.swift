import SwiftUI

struct DevChallengeSectionView: View {
    let state: Loadable<String>
    let onGenerate: () -> Void
    let onFetch: () -> Void

    var body: some View {
        Section {
            LabeledContent {
                Text(verbatim: Self.detail(state)).font(.caption.monospaced())
            } label: {
                Text(verbatim: "Deck")
            }
            Button(action: onFetch) { Text(verbatim: "Fetch today's deck") }
            Button(action: onGenerate) { Text(verbatim: "Regenerate deck with AI") }
        } header: {
            Text(verbatim: "Challenge")
        }
    }

    private static func detail(_ state: Loadable<String>) -> String {
        switch state {
        case .idle: "never"
        case .loading: "working…"
        case let .loaded(summary): summary
        case let .failed(error): "FAILED — \(error)"
        }
    }
}
