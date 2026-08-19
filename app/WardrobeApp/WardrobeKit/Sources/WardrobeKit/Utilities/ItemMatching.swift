import Foundation

enum ItemMatching {
    /// ponytail: every constant below is a first guess. §13 of the design doc
    /// says thresholds can only be calibrated once real user photos exist — they
    /// live here together so that calibration is a one-line change.
    enum Tuning {
        static let colorSpread: Float = 40
        static let printSpread: Float = 1.2
        static let aspectSpread: Float = 0.5

        static let colorWeight: Float = 0.4
        static let printWeight: Float = 0.4
        static let aspectWeight: Float = 0.2

        static let likely: Float = 0.80
        static let uncertain: Float = 0.55
        static let maskQualityPenalty: Float = 0.1
        static let maxCandidates = 3
    }

    static func candidates(
        for fingerprint: ItemFingerprint,
        category: GarmentCategory,
        among stored: [ItemFingerprint],
        categories: [UUID: GarmentCategory]
    ) -> [ItemMatch] {
        let comparable = stored.filter {
            $0.itemID != fingerprint.itemID
                && $0.version == fingerprint.version
                && categories[$0.itemID] == category
        }
        guard !comparable.isEmpty else { return [] }

        var best: [UUID: Float] = [:]
        for candidate in comparable {
            let score = score(fingerprint, candidate)
            best[candidate.itemID] = max(best[candidate.itemID] ?? 0, score)
        }

        let floor = Tuning.uncertain + penalty(for: fingerprint)
        return best
            .filter { $0.value >= floor }
            .sorted { $0.value > $1.value }
            .prefix(Tuning.maxCandidates)
            .map { ItemMatch(itemID: $0.key, score: $0.value, confidence: confidence($0.value, fingerprint)) }
    }

    // MARK: Scoring

    struct Comparison: Equatable {
        let colorDelta: Float
        let printDistance: Float?
        let aspectDelta: Float
        let maskQuality: Float
        let score: Float
    }

    static func score(_ lhs: ItemFingerprint, _ rhs: ItemFingerprint) -> Float {
        compare(lhs, rhs).score
    }

    static func compare(_ lhs: ItemFingerprint, _ rhs: ItemFingerprint) -> Comparison {
        let colorDelta = deltaE(lhs.colorLab, rhs.colorLab)
        let aspectDelta = abs(lhs.aspectRatio - rhs.aspectRatio)
        let printDistance = GarmentFingerprinting.distance(lhs.featurePrint, rhs.featurePrint)

        let color = colorDelta.map { similarity($0, spread: Tuning.colorSpread) } ?? 0
        let aspect = similarity(aspectDelta, spread: Tuning.aspectSpread)
        let print = printDistance.map { similarity($0, spread: Tuning.printSpread) }

        let quality = min(lhs.maskQuality, rhs.maskQuality)
        let aspectWeight = Tuning.aspectWeight * quality
        let colorWeight = Tuning.colorWeight + (Tuning.aspectWeight - aspectWeight)

        let score: Float = if let print {
            color * colorWeight + print * Tuning.printWeight + aspect * aspectWeight
        } else {
            (color * colorWeight + aspect * aspectWeight) / (colorWeight + aspectWeight)
        }

        return Comparison(
            colorDelta: colorDelta ?? .infinity,
            printDistance: printDistance,
            aspectDelta: aspectDelta,
            maskQuality: quality,
            score: score
        )
    }

    private static func deltaE(_ lhs: [Float], _ rhs: [Float]) -> Float? {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return nil }
        return zip(lhs, rhs).map { ($0 - $1) * ($0 - $1) }.reduce(0, +).squareRoot()
    }

    private static func similarity(_ distance: Float, spread: Float) -> Float {
        1 - min(1, max(0, distance) / spread)
    }

    private static func penalty(for fingerprint: ItemFingerprint) -> Float {
        (1 - min(1, max(0, fingerprint.maskQuality))) * Tuning.maskQualityPenalty
    }

    private static func confidence(_ score: Float, _ fingerprint: ItemFingerprint) -> ItemMatch.Confidence {
        score >= Tuning.likely + penalty(for: fingerprint) ? .likely : .uncertain
    }
}
