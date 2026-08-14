import Foundation

/// One browsable challenge prompt (PRD FR-007). Text-only is the permanent
/// fallback, so nothing here can block the loop.
public struct ChallengeCard: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let prompt: String

    public init(id: UUID = UUID(), prompt: String) {
        self.id = id
        self.prompt = prompt
    }
}
