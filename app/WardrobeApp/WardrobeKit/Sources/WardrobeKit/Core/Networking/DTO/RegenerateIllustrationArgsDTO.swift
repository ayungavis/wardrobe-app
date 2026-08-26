import Foundation

struct RegenerateIllustrationArgsDTO: Encodable, Sendable, Equatable {
    let itemId: UUID
    let note: String?
}
