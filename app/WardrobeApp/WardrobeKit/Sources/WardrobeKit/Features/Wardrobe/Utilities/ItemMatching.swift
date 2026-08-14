import Foundation

/// Decides which wardrobe items might be the garment just scanned
/// (docs/wardrobe-generation.md §7).
///
/// Runs before anything is uploaded or generated: a garment the user already
/// owns costs no render, and its illustration stays the same picture it has
/// always been.
enum ItemMatching {
    /// ponytail: every constant below is a first guess. §13 of the design doc
    /// says thresholds can only be calibrated once real user photos exist — they
    /// live here together so that calibration is a one-line change.
    enum Tuning {
        /// ΔE in Lab at which two colours count as completely different.
        static let colorSpread: Float = 40
        /// Feature-print L2 at which two garments count as unrelated. The scale
        /// is revision-dependent and undocumented, so this is the least certain
        /// number here.
        static let printSpread: Float = 1.2
        /// Aspect-ratio gap at which two silhouettes count as unrelated.
        static let aspectSpread: Float = 0.5

        static let colorWeight: Float = 0.4
        static let printWeight: Float = 0.4
        static let aspectWeight: Float = 0.2

        static let likely: Float = 0.80
        static let uncertain: Float = 0.55
        /// A torn mask makes the silhouette unreliable, so the bar goes up.
        static let maskQualityPenalty: Float = 0.1
        static let maxCandidates = 3
    }

    /// Best first, capped at `Tuning.maxCandidates`.
    static func candidates(
        for fingerprint: ItemFingerprint,
        category: GarmentCategory,
        among stored: [ItemFingerprint],
        categories: [UUID: GarmentCategory]
    ) -> [ItemMatch] {
        // Hard filters: a top is never a bottom, and vectors from different
        // Vision revisions are not comparable.
        let comparable = stored.filter {
            $0.itemID != fingerprint.itemID
                && $0.version == fingerprint.version
                && categories[$0.itemID] == category
        }
        guard !comparable.isEmpty else { return [] }

        // An item owns one fingerprint per confirmed wear; it is judged by its
        // closest one, which is the whole reason all of them are kept.
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

    static func score(_ lhs: ItemFingerprint, _ rhs: ItemFingerprint) -> Float {
        let color = colorScore(lhs.colorLab, rhs.colorLab)
        let aspect = similarity(abs(lhs.aspectRatio - rhs.aspectRatio), spread: Tuning.aspectSpread)
        let print = GarmentFingerprinting.distance(lhs.featurePrint, rhs.featurePrint)
            .map { similarity($0, spread: Tuning.printSpread) }

        // A torn mask makes the silhouette untrustworthy, so its weight moves to
        // colour rather than being thrown away.
        let quality = min(lhs.maskQuality, rhs.maskQuality)
        let aspectWeight = Tuning.aspectWeight * quality
        let colorWeight = Tuning.colorWeight + (Tuning.aspectWeight - aspectWeight)

        guard let print else {
            // Vision failed for one side (§A5): renormalise over what is left
            // instead of scoring the garment as a mismatch.
            let total = colorWeight + aspectWeight
            return (color * colorWeight + aspect * aspectWeight) / total
        }
        return color * colorWeight + print * Tuning.printWeight + aspect * aspectWeight
    }

    private static func colorScore(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        let deltaE = zip(lhs, rhs).map { ($0 - $1) * ($0 - $1) }.reduce(0, +).squareRoot()
        return similarity(deltaE, spread: Tuning.colorSpread)
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
