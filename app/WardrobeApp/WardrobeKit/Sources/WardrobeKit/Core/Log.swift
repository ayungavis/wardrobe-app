import Foundation
import os

/// Central loggers per category. Never log photos, search queries, or raw
/// item names (PRD §18/§24 privacy rules).
public enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.ayungavis.WardrobeApp"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let network = Logger(subsystem: subsystem, category: "network")
    public static let ui = Logger(subsystem: subsystem, category: "ui")

    // ponytail: set-once static hook so WardrobeKit stays free of the Sentry
    // dependency; the app target assigns SentrySDK.capture here at startup.
    public nonisolated(unsafe) static var errorReporter: (@Sendable (Error) -> Void)?

    /// Logs a non-fatal error and forwards it to the crash reporter if configured.
    public static func report(_ error: Error, logger: Logger = Log.app) {
        logger.error("\(String(describing: error), privacy: .public)")
        errorReporter?(error)
    }
}
