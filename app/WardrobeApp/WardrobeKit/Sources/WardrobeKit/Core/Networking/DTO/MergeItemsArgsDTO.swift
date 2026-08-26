import Foundation

struct MergeItemsArgsDTO: Encodable, Sendable, Equatable {
    let winnerId: UUID
    let loserId: UUID
}
