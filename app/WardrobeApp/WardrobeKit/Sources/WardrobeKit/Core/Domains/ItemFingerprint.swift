import Foundation

/// What identifies a garment across days. Computed from the normalized cut-out,
/// never from the generated illustration — the illustration is stochastic and
/// deliberately erases the detail that tells two beige shirts apart
/// (docs/wardrobe-generation.md §7).
///
/// An item accumulates one of these per confirmed wear, so matching gets
/// stronger over time.
public struct ItemFingerprint: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let itemID: UUID
    /// Algorithm + Vision revision. Only fingerprints of the same version may
    /// be compared; a mismatch means recompute from the stored cut-out.
    public let version: String
    /// Shadow-suppressed dominant colours.
    public let colorLab: [Float]
    public let aspectRatio: Float
    /// Raw `VNFeaturePrintObservation.data` — the observation itself cannot be
    /// rehydrated from disk, so distances are computed over these floats.
    public let featurePrint: Data
    /// 0...1. Low values mean a torn mask, which lowers the silhouette's weight
    /// and raises the confirmation threshold.
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
