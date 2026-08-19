import Foundation

public struct ItemFingerprint: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let itemID: UUID
    public let version: String
    public let colorLab: [Float]
    public let aspectRatio: Float
    public let featurePrint: Data
    public let maskQuality: Float
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        itemID: UUID,
        version: String,
        colorLab: [Float],
        aspectRatio: Float,
        featurePrint: Data,
        maskQuality: Float,
        createdAt: Date
    ) {
        self.id = id
        self.itemID = itemID
        self.version = version
        self.colorLab = colorLab
        self.aspectRatio = aspectRatio
        self.featurePrint = featurePrint
        self.maskQuality = maskQuality
        self.createdAt = createdAt
    }
}
