import Sentry
import SwiftUI
import WardrobeKit

@main
struct WardrobeAppApp: App {
    @Environment(\.scenePhase) private var scenePhase

    private let container = AppContainer()

    init() {
        Self.startSentryIfConfigured()
    }

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
        }
        // Draft writes are coalesced, so this is where the last one is made to
        // land — without it, backgrounding mid-edit could lose the burst that
        // the timer had not got to yet (FR-004).
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            Task { await container.flushDrafts() }
        }
    }

    /// DSN comes from Info.plist via xcconfig. A missing or unusable DSN (a dev
    /// machine without a Sentry account, or a truncated xcconfig value) simply
    /// leaves the SDK off — starting it with a broken DSN only produces a
    /// stream of fatal log lines.
    private static func startSentryIfConfigured() {
        guard let dsn = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String,
              let url = URL(string: dsn), url.host?.isEmpty == false
        else {
            Log.app.info("Sentry disabled: no usable DSN configured")
            return
        }

        SentrySDK.start { options in
            options.dsn = dsn
            options.environment = Bundle.main
                .object(forInfoDictionaryKey: "SentryEnvironment") as? String ?? "development"
        }
        Log.errorReporter = { SentrySDK.capture(error: $0) }
    }
}
