import Foundation

public struct SessionTokens: Equatable, Codable, Sendable {
    public let accountID: UUID
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public let refreshExpiresAt: Date

    public init(
        accountID: UUID,
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        refreshExpiresAt: Date
    ) {
        self.accountID = accountID
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.refreshExpiresAt = refreshExpiresAt
    }

    public func isUsable(at instant: Date, margin: TimeInterval = 60) -> Bool {
        instant.addingTimeInterval(margin) < expiresAt
    }

    public func canRefresh(at instant: Date) -> Bool {
        instant < refreshExpiresAt
    }
}
