import Foundation

public struct AppleAccount: Equatable, Codable, Sendable {
    public let userID: String
    public var fullName: String?
    public var email: String?

    public init(userID: String, fullName: String? = nil, email: String? = nil) {
        self.userID = userID
        self.fullName = fullName
        self.email = email
    }

    public func merged(with newer: AppleAccount) -> AppleAccount {
        guard newer.userID == userID else { return newer }
        return AppleAccount(
            userID: userID,
            fullName: newer.fullName ?? fullName,
            email: newer.email ?? email
        )
    }
}
