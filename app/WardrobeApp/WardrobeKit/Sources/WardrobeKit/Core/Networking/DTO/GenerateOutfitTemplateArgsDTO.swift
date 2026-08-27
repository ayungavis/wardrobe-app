import Foundation

struct GenerateOutfitTemplateArgsDTO: Encodable, Sendable, Equatable {
    let requestId: UUID
    let template: String
    let personMediaId: UUID
    let garments: [TemplateGarmentDTO]
}

struct TemplateGarmentDTO: Encodable, Sendable, Equatable {
    let mediaId: UUID
    let name: String?
    let wears: Int64
}
