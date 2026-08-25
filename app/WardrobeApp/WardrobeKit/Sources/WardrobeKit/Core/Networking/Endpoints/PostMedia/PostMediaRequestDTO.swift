import Foundation

struct PostMediaRequestDTO: Encodable, Sendable {
    let mediaId: UUID
    let kind: String
    let contentType: String
    let byteSize: Int64?
}
