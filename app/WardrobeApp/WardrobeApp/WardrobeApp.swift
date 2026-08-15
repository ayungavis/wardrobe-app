import Sentry
import SwiftUI
import WardrobeKit

@main
struct WardrobeAppApp: App {
    private let container = AppContainer()

    init() {
        Self.startSentryIfConfigured()
    }

    var body: some Scene {
        WindowGroup {
//           ZStack{
//                Image("appBG")
//                    .resizable()
//                    .ignoresSafeArea()
//                RootView(container: container)
//            }
            RootView(container: container)
                //.background(Color.red.ignoresSafeArea())
//                .background(
//                                Image("appBG")
//                                    .resizable()
//                                    .ignoresSafeArea()
//                            )
        }
    }

    /// DSN comes from Info.plist via xcconfig. Empty DSN (e.g. a dev machine
    /// without a Sentry account) simply leaves the SDK off.
    private static func startSentryIfConfigured() {
        guard let dsn = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String,
              !dsn.isEmpty
        else {
            Log.app.info("Sentry disabled: no DSN configured")
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

