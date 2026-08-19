import Foundation

public struct ChallengeCard: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let prompt: String

    public init(id: UUID = UUID(), prompt: String) {
        self.id = id
        self.prompt = prompt
    }
}
