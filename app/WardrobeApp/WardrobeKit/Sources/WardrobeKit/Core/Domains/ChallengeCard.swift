import Foundation

public struct ChallengeCard: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let title: String?
    public let prompt: String
    public let topItemID: UUID?
    public let bottomItemID: UUID?
    public let isFreestyle: Bool

    public init(
        id: UUID = UUID(),
        title: String? = nil,
        prompt: String,
        topItemID: UUID? = nil,
        bottomItemID: UUID? = nil,
        isFreestyle: Bool = false
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.topItemID = topItemID
        self.bottomItemID = bottomItemID
        self.isFreestyle = isFreestyle
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        prompt = try container.decode(String.self, forKey: .prompt)
        topItemID = try container.decodeIfPresent(UUID.self, forKey: .topItemID)
        bottomItemID = try container.decodeIfPresent(UUID.self, forKey: .bottomItemID)
        isFreestyle = try container.decodeIfPresent(Bool.self, forKey: .isFreestyle) ?? false
    }
}

public extension ChallengeCard {
    static let freestyle = ChallengeCard(id: freestyleID, prompt: "Freestyle", isFreestyle: true)

    var outfit: (top: UUID, bottom: UUID)? {
        guard let topItemID, let bottomItemID else { return nil }
        return (topItemID, bottomItemID)
    }

    // Type safety: a compile-time-constant UUID literal. Both freestyle entry
    // points must mint the same card id, so it cannot be generated per call.
    // swiftlint:disable:next force_unwrapping
    private static let freestyleID = UUID(uuidString: "019205f0-0000-7000-8000-000000000001")!
}
