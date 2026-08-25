import Foundation

struct PostSyncResponseDTO: Decodable, Sendable {
    let results: [MutationResultDTO]
}

struct MutationResultDTO: Decodable, Sendable {
    let id: UUID
    let name: String
    let outcome: MutationOutcomeDTO

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        switch try container.decode(String.self, forKey: .status) {
        case "applied":
            outcome = try .applied(record: container.decode(JSONValue.self, forKey: .record))
        case "failed":
            outcome = try .failed(container.decode(ErrorDetailDTO.self, forKey: .error))
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .status, in: container, debugDescription: "unknown status \(other)"
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case status
        case record
        case error
    }
}

enum MutationOutcomeDTO: Sendable {
    case applied(record: JSONValue)
    case failed(ErrorDetailDTO)
}
