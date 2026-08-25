import Foundation

struct DevSessionInfo: Equatable, Sendable {
    let accountID: UUID
    let accessExpiresAt: Date
    let refreshExpiresAt: Date
    let isAccessUsable: Bool
    let whoami: Whoami?

    struct Whoami: Equatable, Sendable {
        let accountID: UUID
        let sessionID: UUID
    }
}
