import Foundation
import os

public enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.ayungavis.WardrobeApp"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let network = Logger(subsystem: subsystem, category: "network")
    public static let ui = Logger(subsystem: subsystem, category: "ui")

    // ponytail: named fields rather than a dictionary, so an item name or any
    // other user-written text has nowhere to be put. PRD §18.12 keeps that out
    // of logs, and a shape cannot forget the way a convention can.
    public struct Context: Sendable, Equatable {
        public var operation: String?
        public var endpoint: String?
        public var requestID: String?
        public var status: Int?

        public init(
            operation: String? = nil,
            endpoint: String? = nil,
            requestID: String? = nil,
            status: Int? = nil
        ) {
            self.operation = operation
            self.endpoint = endpoint
            self.requestID = requestID
            self.status = status
        }

        public var isEmpty: Bool {
            self == Context()
        }

        public var summary: String {
            [
                operation.map { "op=\($0)" },
                endpoint.map { "endpoint=\($0)" },
                status.map { "status=\($0)" },
                requestID.map { "requestId=\($0)" },
            ]
            .compactMap(\.self)
            .joined(separator: " ")
        }
    }

    // ponytail: set-once static hooks so WardrobeKit stays free of the Sentry
    // dependency; the app target assigns the reporter and AppContainer the sink.
    public nonisolated(unsafe) static var errorReporter: (@Sendable (Error, Context) -> Void)?
    public nonisolated(unsafe) static var diagnosticsSink: (@Sendable (Error, Context) -> Void)?

    // ponytail: the newest trail stands in for a Sentry breadcrumb, so a caller
    // that reports without context still carries the request id its failure came
    // with. Replace it with real breadcrumbs if the trail ever needs a history.
    private nonisolated(unsafe) static var lastTrail = Context()

    public static func trail(_ error: Error, context: Context, logger: Logger = Log.network) {
        logger.error("\(String(describing: error), privacy: .public) \(context.summary, privacy: .public)")
        lastTrail = context
        diagnosticsSink?(error, context)
    }

    public static func report(
        _ error: Error,
        context: Context = Context(),
        logger: Logger = Log.app
    ) {
        let carried = context.isEmpty ? lastTrail : context
        let described = String(describing: error)
        if carried.isEmpty {
            logger.error("\(described, privacy: .public)")
        } else {
            logger.error("\(described, privacy: .public) \(carried.summary, privacy: .public)")
        }
        errorReporter?(error, carried)
        diagnosticsSink?(error, carried)
    }
}
