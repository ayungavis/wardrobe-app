import Foundation

enum SyncMutation: Sendable {
    case upsertItem(UpsertItemArgsDTO)
    case deleteItem(DeleteItemArgsDTO)
    case upsertPreferences(UpsertPreferencesArgsDTO)
    case resolveCompletion(ResolveCompletionArgsDTO)
    case completeChallenge(CompleteChallengeArgsDTO)

    var name: String {
        switch self {
        case .upsertItem: "upsertItem"
        case .deleteItem: "deleteItem"
        case .upsertPreferences: "upsertPreferences"
        case .resolveCompletion: "resolveCompletion"
        case .completeChallenge: "completeChallenge"
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
        case let .upsertPreferences(args): return try encoder.encode(args)
        case let .resolveCompletion(args): return try encoder.encode(args)
        case let .completeChallenge(args): return try encoder.encode(args)
        }
    }
}
