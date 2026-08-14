import Foundation
import Testing
@testable import WardrobeKit

struct MatchBenchmarkTests {
    private let version = "v1+vision2"

    private func makeSample(
        group: Int,
        category: GarmentCategory = .top,
        version: String? = nil,
        color: [Float] = [70, 5, 15],
        aspect: Float = 0.8,
        print vector: [Float]? = [1, 0, 0, 0]
    ) -> BenchmarkSample {
        let id = UUID()
        let data = vector.map { floats in
            floats.withUnsafeBufferPointer { Data(buffer: $0) }
        } ?? Data()
        return BenchmarkSample(
            id: id,
            groupIndex: group,
            category: category,
            fingerprint: ItemFingerprint(
                itemID: id, version: version ?? self.version, colorLab: color,
                aspectRatio: aspect, featurePrint: data, maskQuality: 1, createdAt: Date()
            )
        )
    }

    // MARK: Pairing

    @Test func pairsAreLabelledByTheirGroups() {
        let report = MatchBenchmark.report(for: [
            makeSample(group: 0), makeSample(group: 0), makeSample(group: 1),
        ])

        #expect(report.sampleCount == 3)
        #expect(report.groupCount == 2)
        #expect(report.samePairCount == 1)
        #expect(report.differentPairCount == 2)
    }

    /// The benchmark must apply the same hard filters as `ItemMatching`, or it
    /// scores the matcher on comparisons the matcher never makes.
    @Test func pairsAcrossCategoriesOrVisionRevisionsAreNotJudged() {
        let report = MatchBenchmark.report(for: [
            makeSample(group: 0),
            makeSample(group: 0, category: .bottom),
            makeSample(group: 0, version: "v1+vision1"),
        ])

        #expect(report.samePairCount == 0)
        #expect(report.differentPairCount == 0)
    }

    // MARK: Signals

    @Test func aPerfectlySeparatedSetReachesF1One() {
        let report = MatchBenchmark.report(for: [
            makeSample(group: 0, color: [70, 5, 15], print: [1, 0, 0, 0]),
            makeSample(group: 0, color: [70, 5, 15], print: [1, 0, 0, 0]),
            makeSample(group: 1, color: [20, -30, -30], print: [0, 1, 0, 0]),
            makeSample(group: 1, color: [20, -30, -30], print: [0, 1, 0, 0]),
        ])
        let score = try? #require(report.signals.first { $0.name == "score" })

        #expect(score?.best?.f1Score == 1)
        #expect((score?.same?.lowest ?? 0) > (score?.different?.highest ?? 1))
    }

    /// The point of the per-signal rows: a set where colour decides everything
    /// must say so, otherwise it cannot tell us whether a new embedding helps.
    @Test func eachSignalIsScoredOnItsOwn() {
        let report = MatchBenchmark.report(for: [
            makeSample(group: 0, color: [70, 5, 15], aspect: 0.4),
            makeSample(group: 0, color: [70, 5, 15], aspect: 1.6),
            makeSample(group: 1, color: [20, -30, -30], aspect: 0.4),
            makeSample(group: 1, color: [20, -30, -30], aspect: 1.6),
        ])
        let colour = try? #require(report.signals.first { $0.name == "colour dE" })
        let aspect = try? #require(report.signals.first { $0.name == "aspect" })

        #expect(colour?.best?.f1Score == 1)
        #expect((aspect?.best?.f1Score ?? 1) < 1) // shape is noise in this set
    }

    /// Vision can fail (§A5). Those pairs say nothing about the feature print,
    /// so they must not be counted against it — but they still have a score.
    @Test func pairsWithoutAFeaturePrintAreDroppedFromThatSignalOnly() {
        let report = MatchBenchmark.report(for: [
            makeSample(group: 0, print: nil), makeSample(group: 0, print: nil),
        ])
        let featurePrint = try? #require(report.signals.first { $0.name == "feature print" })

        #expect(report.samePairCount == 1)
        #expect(featurePrint?.same == nil)
        #expect(featurePrint?.best == nil)
    }

    // MARK: Worst cases

    @Test func theWorstCasesAreTheOnesWeWouldGetWrong() {
        let missed = [makeSample(group: 0, color: [90, 0, 0]), makeSample(group: 0, color: [10, 0, 0])]
        let invented = [makeSample(group: 1), makeSample(group: 2)]
        let report = MatchBenchmark.report(for: missed + invented)

        // Groups 1 and 2 are identical apart from their label, so they score
        // near the top; the two group-0 samples are the same garment yet score
        // below them. That inversion is exactly what a benchmark exists to show.
        let worstMiss = report.worstFalseNegatives.first?.score ?? 1
        let worstInvention = report.worstFalsePositives.first?.score ?? 0
        #expect(worstInvention > 0.95)
        #expect(worstMiss < worstInvention)
    }

    @Test func anEmptySetProducesAnEmptyReportRatherThanACrash() {
        let report = MatchBenchmark.report(for: [])

        #expect(report.sampleCount == 0)
        #expect(report.signals.allSatisfy { $0.best == nil })
        #expect(!report.formatted.isEmpty)
    }
}
