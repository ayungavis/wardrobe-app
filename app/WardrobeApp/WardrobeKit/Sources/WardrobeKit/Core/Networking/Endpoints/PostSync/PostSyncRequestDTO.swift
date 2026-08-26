import Foundation

struct PostSyncRequestDTO: Encodable, Sendable {
    let mutations: [MutationRequestDTO]
}

struct MutationRequestDTO: Encodable, Sendable, Equatable {
    let id: UUID
    let name: String
    let args: JSONValue
}
