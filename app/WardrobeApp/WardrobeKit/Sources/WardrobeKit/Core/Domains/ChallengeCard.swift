import Foundation

public struct ChallengeCard: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let prompt: String
    public let isFreestyle: Bool

    public init(id: UUID = UUID(), prompt: String, isFreestyle: Bool = false) {
        self.id = id
        self.prompt = prompt
        self.isFreestyle = isFreestyle
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        prompt = try container.decode(String.self, forKey: .prompt)
        isFreestyle = try container.decodeIfPresent(Bool.self, forKey: .isFreestyle) ?? false
    }
}

public extension ChallengeCard {
    static let freestyle = ChallengeCard(id: freestyleID, prompt: "Freestyle", isFreestyle: true)

    // Type safety: a compile-time-constant UUID literal. Both freestyle entry
    // points must mint the same card id, so it cannot be generated per call.
    // swiftlint:disable:next force_unwrapping
    private static let freestyleID = UUID(uuidString: "019205f0-0000-7000-8000-000000000001")!
}
