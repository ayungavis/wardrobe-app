import Foundation

struct PostSessionsAppleRequestDTO: Encodable, Sendable {
    let deviceId: UUID
    let identityToken: String
    let nonce: String
}
