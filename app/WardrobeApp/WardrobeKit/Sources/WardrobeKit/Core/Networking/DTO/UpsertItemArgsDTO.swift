import Foundation

struct UpsertItemArgsDTO: Encodable, Sendable {
    let id: UUID
    var category: ItemFieldDTO?
    var name: ItemFieldDTO?
    var color: ItemFieldDTO?
    var garmentType: ItemFieldDTO?
    var description: ItemFieldDTO?
    var cutout: CutoutArgsDTO?
}

struct ItemFieldDTO: Encodable, Sendable, Equatable {
    let value: String?
    let rev: Int64

    // ponytail: written by hand because synthesised Encodable uses
    // encodeIfPresent for Optionals, which drops the key. A present null means
    // "clear this field"; an absent key means "leave it alone", and the server
    // reads only the fields that are present.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
        try container.encode(rev, forKey: .rev)
    }

    private enum CodingKeys: String, CodingKey {
        case value
        case rev
    }
}

struct CutoutArgsDTO: Encodable, Sendable, Equatable {
    let id: UUID
    let mediaObjectId: UUID
    let sourcePhotoId: UUID?
}
