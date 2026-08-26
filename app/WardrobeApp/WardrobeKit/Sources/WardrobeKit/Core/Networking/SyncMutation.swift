import Foundation

enum SyncMutation: Sendable {
    static let completeChallengeName = "completeChallenge"

    case upsertItem(UpsertItemArgsDTO)
    case deleteItem(DeleteItemArgsDTO)
    case deleteCompletion(DeleteCompletionArgsDTO)
    case mergeItems(MergeItemsArgsDTO)
    case regenerateIllustration(RegenerateIllustrationArgsDTO)
    case upsertPreferences(UpsertPreferencesArgsDTO)
    case resolveCompletion(ResolveCompletionArgsDTO)
    case completeChallenge(CompleteChallengeArgsDTO)
    case upsertChallengeContext(UpsertChallengeContextArgsDTO)
    case generateChallengeDeck(GenerateChallengeDeckArgsDTO)
    case generateOutfitTemplate(GenerateOutfitTemplateArgsDTO)

    var name: String {
        switch self {
        case .upsertItem: "upsertItem"
        case .deleteItem: "deleteItem"
        case .deleteCompletion: "deleteCompletion"
        case .mergeItems: "mergeItems"
        case .regenerateIllustration: "regenerateIllustration"
        case .upsertPreferences: "upsertPreferences"
        case .resolveCompletion: "resolveCompletion"
        case .completeChallenge: Self.completeChallengeName
        case .upsertChallengeContext: "upsertChallengeContext"
        case .generateChallengeDeck: "generateChallengeDeck"
        case .generateOutfitTemplate: "generateOutfitTemplate"
        }
    }

    func queued(id: UUID = UUID()) throws -> OutboxMutation {
        try OutboxMutation(id: id, name: name, payload: encodedArguments())
    }

    func encodedArguments() throws -> Data {
        guard let arguments else { throw AppError.unexpected }
        return try JSONEncoder.api.encode(arguments)
    }

    private var arguments: (any Encodable & Sendable)? {
        switch self {
        case let .upsertItem(args): args
        case let .deleteItem(args): args
        case let .deleteCompletion(args): args
        case let .mergeItems(args): args
        case let .regenerateIllustration(args): args
        default: laterArguments
        }
    }

    private var laterArguments: (any Encodable & Sendable)? {
        switch self {
        case let .upsertPreferences(args): args
        case let .resolveCompletion(args): args
        case let .completeChallenge(args): args
        case let .upsertChallengeContext(args): args
        case let .generateChallengeDeck(args): args
        case let .generateOutfitTemplate(args): args
        default: nil
        }
    }
}
