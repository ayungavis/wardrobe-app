import Foundation

struct MediaGrantDTO: Decodable, Sendable {
    let mediaId: UUID
    let url: String
    let expiresAt: Date
    let byteSize: Int64?
}
