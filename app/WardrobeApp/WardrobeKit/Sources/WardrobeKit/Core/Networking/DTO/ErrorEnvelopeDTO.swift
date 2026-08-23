import Foundation

struct ErrorDetailDTO: Decodable, Sendable {
    let code: String
    let message: String
}

struct ErrorEnvelopeDTO: Decodable, Sendable {
    let error: ErrorDetailDTO
}
