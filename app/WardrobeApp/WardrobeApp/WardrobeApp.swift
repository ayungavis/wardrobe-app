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
        Log.breadcrumbRecorder = { error, context in
            let crumb = Breadcrumb(level: .warning, category: "http")
            crumb.message = String(describing: error)
            var data: [String: Any] = [:]
            if let operation = context.operation {
                data["operation"] = operation
            }
            if let endpoint = context.endpoint {
                data["endpoint"] = endpoint
            }
            if let requestID = context.requestID {
                data["request_id"] = requestID
            }
            if let status = context.status {
                data["status"] = status
            }
            crumb.data = data
            SentrySDK.addBreadcrumb(crumb)
        }
        Log.errorReporter = { error, context in
            SentrySDK.capture(error: error) { scope in
                if let operation = context.operation {
                    scope.setTag(value: operation, key: "operation")
                }
                if let endpoint = context.endpoint {
                    scope.setTag(value: endpoint, key: "endpoint")
                }
                if let requestID = context.requestID {
                    scope.setTag(value: requestID, key: "request_id")
                }
                if let status = context.status {
                    scope.setTag(value: "\(status)", key: "status")
                }
            }
        }
    }
}
