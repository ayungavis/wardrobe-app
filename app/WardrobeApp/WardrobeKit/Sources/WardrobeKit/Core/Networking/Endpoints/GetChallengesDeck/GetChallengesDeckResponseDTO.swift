import Foundation

struct GetChallengesDeckResponseDTO: Decodable, Sendable {
    let localDate: String
    let source: String
    let cards: [ChallengeDeckCardDTO]
}

struct ChallengeDeckCardDTO: Decodable, Sendable {
    let id: UUID
    let title: String?
    let prompt: String
    let topItemId: UUID?
    let bottomItemId: UUID?
}
