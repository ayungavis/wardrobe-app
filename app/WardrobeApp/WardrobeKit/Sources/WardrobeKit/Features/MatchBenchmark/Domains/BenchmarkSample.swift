import Foundation

struct BenchmarkSample: Identifiable, Equatable, Sendable {
    let id: UUID
    let groupIndex: Int
    let category: GarmentCategory
    let fingerprint: ItemFingerprint
}
