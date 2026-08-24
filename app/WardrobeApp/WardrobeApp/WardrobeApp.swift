import DesignSystem
import Sentry
import SwiftUI
import WardrobeKit

@main
struct WardrobeAppApp: App {
    @Environment(\.scenePhase) private var scenePhase

    private let container = AppContainer()

    init() {
        FontRegistration.registerCustomFonts()
        Self.startSentryIfConfigured()
    }

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            Task { await container.flushDrafts() }
        }
    }

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
