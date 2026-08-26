import Foundation

enum SyncMutation: Sendable {
    static let completeChallengeName = "completeChallenge"

    case upsertItem(UpsertItemArgsDTO)
    case deleteItem(DeleteItemArgsDTO)
    case mergeItems(MergeItemsArgsDTO)
    case regenerateIllustration(RegenerateIllustrationArgsDTO)
    case upsertPreferences(UpsertPreferencesArgsDTO)
    case resolveCompletion(ResolveCompletionArgsDTO)
    case completeChallenge(CompleteChallengeArgsDTO)

    var name: String {
        switch self {
        case .upsertItem: "upsertItem"
        case .deleteItem: "deleteItem"
        case .mergeItems: "mergeItems"
        case .regenerateIllustration: "regenerateIllustration"
        case .upsertPreferences: "upsertPreferences"
        case .resolveCompletion: "resolveCompletion"
        case .completeChallenge: Self.completeChallengeName
        }
    }

    func queued(id: UUID = UUID()) throws -> OutboxMutation {
        try OutboxMutation(id: id, name: name, payload: encodedArguments())
    }

    func encodedArguments() throws -> Data {
        let encoder = JSONEncoder.api
        switch self {
        case let .upsertItem(args): return try encoder.encode(args)
        case let .deleteItem(args): return try encoder.encode(args)
        case let .mergeItems(args): return try encoder.encode(args)
        case let .regenerateIllustration(args): return try encoder.encode(args)
        case let .upsertPreferences(args): return try encoder.encode(args)
        case let .resolveCompletion(args): return try encoder.encode(args)
        case let .completeChallenge(args): return try encoder.encode(args)
        }
    }
}
