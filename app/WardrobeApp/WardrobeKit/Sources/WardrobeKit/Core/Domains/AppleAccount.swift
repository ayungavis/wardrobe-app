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

    public var normalized: AppleAccount {
        AppleAccount(accountID: accountID, fullName: fullName?.nonBlank, email: email?.nonBlank)
    }

    public func merged(with newer: AppleAccount) -> AppleAccount {
        guard newer.accountID == accountID else { return newer }
        return AppleAccount(
            accountID: accountID,
            fullName: newer.fullName?.nonBlank ?? fullName,
            email: newer.email?.nonBlank ?? email
        )
    }
}
