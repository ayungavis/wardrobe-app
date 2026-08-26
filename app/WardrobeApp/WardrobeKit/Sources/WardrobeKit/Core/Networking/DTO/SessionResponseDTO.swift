import Foundation

struct SessionResponseDTO: Decodable, Sendable {
    let accountId: UUID
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let refreshExpiresAt: Date
}
