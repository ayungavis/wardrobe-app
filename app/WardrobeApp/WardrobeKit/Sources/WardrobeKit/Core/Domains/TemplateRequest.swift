import Foundation

public struct TemplateRequest: Sendable {
    public struct Garment: Sendable {
        public let cutout: Data
        public let name: String
        public let wears: Int

        public init(cutout: Data, name: String, wears: Int) {
            self.cutout = cutout
            self.name = name
            self.wears = wears
        }
    }

    public let template: OutfitTemplate
    public let photo: Data
    public let garments: [Garment]

    public init(template: OutfitTemplate, photo: Data, garments: [Garment]) {
        self.template = template
        self.photo = photo
        self.garments = garments
    }
}
