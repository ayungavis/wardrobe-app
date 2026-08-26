import Foundation

struct GetWhoamiResponseDTO: Decodable, Sendable {
    let accountId: UUID
    let sessionId: UUID
}
