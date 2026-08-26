import Foundation

public struct AppleProfile: Equatable, Sendable {
    public let fullName: String?
    public let email: String?

    public init(fullName: String?, email: String?) {
        self.fullName = fullName
        self.email = email
    }
}
