import Foundation

/// One detected garment together with the answer: which physical garment it
/// really is.
///
/// The label comes from the user grouping their own photos, one batch per
/// garment — cheaper than any annotation tool and impossible to get subtly
/// wrong.
struct BenchmarkSample: Identifiable, Equatable, Sendable {
    let id: UUID
    /// Ground truth. Two samples are the same garment exactly when this matches.
    let groupIndex: Int
    let category: GarmentCategory
    let fingerprint: ItemFingerprint
}
