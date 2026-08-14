import Foundation
import Testing
@testable import WardrobeKit

struct ItemMatchingTests {
    private let version = "v1+vision2"

    private func makeFingerprint(
        itemID: UUID = UUID(),
        version: String? = nil,
        color: [Float] = [70, 5, 15],
        aspect: Float = 0.8,
        print vector: [Float]? = [1, 0, 0, 0],
        maskQuality: Float = 1
    ) -> ItemFingerprint {
        let data = vector.map { floats in
            floats.withUnsafeBufferPointer { Data(buffer: $0) }
        } ?? Data()
        return ItemFingerprint(
            itemID: itemID,
            version: version ?? self.version,
            colorLab: color,
            aspectRatio: aspect,
            featurePrint: data,
            maskQuality: maskQuality,
            createdAt: Date()
        )
    }

    private func candidates(
        for fingerprint: ItemFingerprint,
        category: GarmentCategory = .top,
        among stored: [ItemFingerprint],
        categories: [UUID: GarmentCategory]? = nil
    ) -> [ItemMatch] {
        let map = categories ?? stored.reduce(into: [:]) { $0[$1.itemID] = GarmentCategory.top }
        return ItemMatching.candidates(for: fingerprint, category: category, among: stored, categories: map)
    }

    // MARK: Hard filters

    @Test func sameGarmentScoresAsLikely() {
        let stored = makeFingerprint()
        let scanned = makeFingerprint(color: stored.colorLab, aspect: stored.aspectRatio)

        let match = candidates(for: scanned, among: [stored]).first

        #expect(match?.itemID == stored.itemID)
        #expect(match?.confidence == .likely)
        #expect((match?.score ?? 0) > 0.95)
    }

    /// A top is never a bottom, however alike they look.
    @Test func differentCategoryNeverMatches() {
        let stored = makeFingerprint()
        let scanned = makeFingerprint(color: stored.colorLab, aspect: stored.aspectRatio)

        let matches = candidates(
            for: scanned, category: .top, among: [stored],
            categories: [stored.itemID: .bottom]
        )

        #expect(matches.isEmpty)
    }

    @Test func fingerprintsFromAnotherVisionRevisionAreSkipped() {
        let stored = makeFingerprint(version: "v1+vision1")
        let scanned = makeFingerprint(color: stored.colorLab, aspect: stored.aspectRatio)

        #expect(candidates(for: scanned, among: [stored]).isEmpty)
    }

    // MARK: Signals

    @Test func aVeryDifferentColourFallsBelowTheBar() {
        let stored = makeFingerprint(color: [30, -20, -35], print: [0, 1, 0, 0])
        let scanned = makeFingerprint(color: [85, 5, 20], print: [1, 0, 0, 0])

        #expect(candidates(for: scanned, among: [stored]).isEmpty)
    }

    @Test func sameColourButAVeryDifferentSilhouetteScoresLower() {
        let shorts = makeFingerprint(aspect: 1.4)
        let trousers = makeFingerprint(aspect: 0.4)
        let sameShape = makeFingerprint(itemID: shorts.itemID, aspect: 1.4)

        #expect(ItemMatching.score(sameShape, trousers) < ItemMatching.score(sameShape, shorts))
    }

    /// Vision can fail (task A5 stores an empty vector); the garment must still
    /// be matchable on colour and shape rather than scoring as a stranger.
    @Test func aMissingFeaturePrintStillScoresOnColourAndShape() {
        let stored = makeFingerprint(print: nil)
        let scanned = makeFingerprint(color: stored.colorLab, aspect: stored.aspectRatio, print: nil)

        let match = candidates(for: scanned, among: [stored]).first

        #expect(match != nil)
        #expect((match?.score ?? 0) > 0.95)
    }

    // MARK: Mask quality

    @Test func aTornMaskRaisesTheBar() {
        let stored = makeFingerprint(color: [70, 5, 15], aspect: 0.8, print: [1, 0.25, 0, 0])
        let clean = makeFingerprint(color: [72, 6, 17], aspect: 0.85, print: [1, 0, 0, 0])
        let torn = makeFingerprint(
            itemID: clean.itemID, color: clean.colorLab, aspect: clean.aspectRatio,
            print: [1, 0, 0, 0], maskQuality: 0.2
        )

        let confident = candidates(for: clean, among: [stored]).first
        let cautious = candidates(for: torn, among: [stored]).first

        #expect(confident?.confidence == .likely)
        #expect(cautious?.confidence == .uncertain)
    }

    // MARK: Ranking

    @Test func anItemIsJudgedByItsClosestFingerprint() {
        let itemID = UUID()
        let distant = makeFingerprint(itemID: itemID, color: [20, -30, -30], print: [0, 1, 0, 0])
        let close = makeFingerprint(itemID: itemID, color: [70, 5, 15], print: [1, 0, 0, 0])
        let scanned = makeFingerprint(color: [70, 5, 15], print: [1, 0, 0, 0])

        let match = candidates(for: scanned, among: [distant, close]).first

        #expect(match?.confidence == .likely)
    }

    @Test func resultsAreRankedAndCapped() {
        let scanned = makeFingerprint()
        let stored = (0 ..< 5).map { index in
            makeFingerprint(color: [70 + Float(index), 5, 15])
        }

        let matches = candidates(for: scanned, among: stored)

        #expect(matches.count <= ItemMatching.Tuning.maxCandidates)
        #expect(matches == matches.sorted { $0.score > $1.score })
    }
}
