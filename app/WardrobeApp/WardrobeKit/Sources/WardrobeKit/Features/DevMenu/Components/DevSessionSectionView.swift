import SwiftUI

struct DevSessionSectionView: View {
    let baseURL: URL
    let state: Loadable<DevSessionInfo>
    let health: Loadable<String>
    let onReload: () -> Void
    let onWhoami: () -> Void
    let onHealth: () -> Void

    var body: some View {
        Section {
            row("Base URL", baseURL.absoluteString)
            row("Server", Self.reachability(health))
            switch state {
            case .idle:
                Text(verbatim: "Not loaded")
            case .loading:
                ProgressView()
            case let .failed(error):
                Text(verbatim: "Failed: \(error)")
            case let .loaded(info):
                row("Account", info.accountID.uuidString)
                row("Access expires", Self.stamp(info.accessExpiresAt))
                row("Refresh expires", Self.stamp(info.refreshExpiresAt))
                row("Access usable", info.isAccessUsable ? "yes" : "no")
                if let whoami = info.whoami {
                    row("whoami account", whoami.accountID.uuidString)
                    row("whoami session", whoami.sessionID.uuidString)
                    row("Matches", whoami.accountID == info.accountID ? "yes" : "NO")
                }
            }

            Button(action: onHealth) { Text(verbatim: "Ping GET /health") }
            Button(action: onReload) { Text(verbatim: "Reload session") }
            Button(action: onWhoami) { Text(verbatim: "Call GET /v1/whoami") }
        } header: {
            Text(verbatim: "Session")
        }
    }

    private func row(_ name: String, _ value: String) -> some View {
        LabeledContent {
            Text(verbatim: value).font(.caption.monospaced())
        } label: {
            Text(verbatim: name)
        }
    }

    private static func reachability(_ health: Loadable<String>) -> String {
        switch health {
        case .idle: "not checked"
        case .loading: "checking…"
        case let .loaded(status): "reachable (\(status))"
        case let .failed(error): "UNREACHABLE — \(error)"
        }
    }

    private static func stamp(_ date: Date) -> String {
        date.formatted(.dateTime.day().month().hour().minute().second())
    }
}
