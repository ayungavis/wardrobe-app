import Foundation

struct PostSessionsRefreshRequestDTO: Encodable, Sendable {
    let refreshToken: String
}
