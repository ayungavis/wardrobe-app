import Foundation

public struct AppleAccount: Equatable, Codable, Sendable {
    public let accountID: UUID
    public var fullName: String?
    public var email: String?

    public init(accountID: UUID, fullName: String? = nil, email: String? = nil) {
        self.accountID = accountID
        self.fullName = fullName
        self.email = email
    }

    public func merged(with newer: AppleAccount) -> AppleAccount {
        guard newer.accountID == accountID else { return newer }
        return AppleAccount(
            accountID: accountID,
            fullName: newer.fullName ?? fullName,
            email: newer.email ?? email
        )
    }
}
