import Foundation

/// Scores the matcher against photos the user labelled, so "is this better?"
/// stops being a matter of opinion.
///
/// Pure: fingerprints in, numbers out. Everything Core ML and camera-shaped
/// lives in the view model, which is why this whole file is testable without a
/// simulator.
enum MatchBenchmark {
    /// Enough failures to see the pattern, few enough to read on a phone.
    static let worstCaseCount = 5

    /// One comparison plus the answer.
    private struct Judged {
        let isSame: Bool
        let pair: BenchmarkReport.Pair
        let comparison: ItemMatching.Comparison
    }

    static func report(for samples: [BenchmarkSample]) -> BenchmarkReport {
        let judged = judge(samples)
        let same = judged.filter(\.isSame)
        let different = judged.filter { !$0.isSame }

        let missed = same.sorted { $0.comparison.score < $1.comparison.score }
        let invented = different.sorted { $0.comparison.score > $1.comparison.score }

        return BenchmarkReport(
            sampleCount: samples.count,
            groupCount: Set(samples.map(\.groupIndex)).count,
            samePairCount: same.count,
            differentPairCount: different.count,
            signals: signals(for: judged),
            worstFalseNegatives: missed.prefix(worstCaseCount).map(\.pair),
            worstFalsePositives: invented.prefix(worstCaseCount).map(\.pair)
        )
    }

    private static func signals(for judged: [Judged]) -> [BenchmarkReport.Signal] {
        let scores: [(Float, Bool)] = judged.map { ($0.comparison.score, $0.isSame) }
        let shipped: [BenchmarkReport.Operating] = [
            operating(label: "shipped uncertain", threshold: ItemMatching.Tuning.uncertain,
                      higherIsCloser: true, values: scores),
            operating(label: "shipped likely", threshold: ItemMatching.Tuning.likely,
                      higherIsCloser: true, values: scores),
        ].compactMap(\.self)

        return [
            signal(named: "score", higherIsCloser: true, values: scores, current: shipped),
            distanceSignal(named: "colour dE", judged) { $0.colorDelta },
            distanceSignal(named: "feature print", judged) { $0.printDistance },
            distanceSignal(named: "aspect", judged) { $0.aspectDelta },
        ]
    }

    /// Same hard filters as `ItemMatching.candidates`: a top is never compared
    /// with a bottom, and vectors from different Vision revisions are not
    /// comparable. A benchmark run against pairs the matcher would never see
    /// would flatter it.
    private static func judge(_ samples: [BenchmarkSample]) -> [Judged] {
        var judged: [Judged] = []
        for (index, left) in samples.enumerated() {
            for right in samples[(index + 1)...] {
                guard left.category == right.category,
                      left.fingerprint.version == right.fingerprint.version else { continue }
                let comparison = ItemMatching.compare(left.fingerprint, right.fingerprint)
                judged.append(Judged(
                    isSame: left.groupIndex == right.groupIndex,
                    pair: pair(left, right, comparison),
                    comparison: comparison
                ))
            }
        }
        return judged
    }

    private static func pair(
        _ left: BenchmarkSample,
        _ right: BenchmarkSample,
        _ comparison: ItemMatching.Comparison
    ) -> BenchmarkReport.Pair {
        BenchmarkReport.Pair(
            left: String(left.id.uuidString.prefix(8)),
            right: String(right.id.uuidString.prefix(8)),
            category: left.category,
            score: comparison.score,
            colorDelta: comparison.colorDelta,
            printDistance: comparison.printDistance,
            aspectDelta: comparison.aspectDelta
        )
    }

    // MARK: Signals

    private static func distanceSignal(
        named name: String,
        _ judged: [Judged],
        _ value: (ItemMatching.Comparison) -> Float?
    ) -> BenchmarkReport.Signal {
        // A pair with no feature print says nothing about the feature print, so
        // it is dropped from that signal rather than counted as a mismatch.
        let values = judged.compactMap { entry -> (Float, Bool)? in
            guard let number = value(entry.comparison), number.isFinite else { return nil }
            return (number, entry.isSame)
        }
        return signal(named: name, higherIsCloser: false, values: values, current: [])
    }

    private static func signal(
        named name: String,
        higherIsCloser: Bool,
        values: [(Float, Bool)],
        current: [BenchmarkReport.Operating]
    ) -> BenchmarkReport.Signal {
        BenchmarkReport.Signal(
            name: name,
            higherIsCloser: higherIsCloser,
            same: distribution(of: values.filter(\.1).map(\.0)),
            different: distribution(of: values.filter { !$0.1 }.map(\.0)),
            best: bestOperating(higherIsCloser: higherIsCloser, values: values),
            current: current
        )
    }

    private static func distribution(of values: [Float]) -> BenchmarkReport.Distribution? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return BenchmarkReport.Distribution(
            count: sorted.count,
            lowest: sorted[0],
            median: sorted[sorted.count / 2],
            highest: sorted[sorted.count - 1]
        )
    }

    /// Sweeps every observed value as a cut point. The set is small — a
    /// benchmark run is tens of garments — so there is nothing to gain from
    /// being cleverer than exhaustive.
    private static func bestOperating(
        higherIsCloser: Bool,
        values: [(Float, Bool)]
    ) -> BenchmarkReport.Operating? {
        Set(values.map(\.0))
            .compactMap {
                operating(label: "best", threshold: $0, higherIsCloser: higherIsCloser, values: values)
            }
            .max { $0.f1Score < $1.f1Score }
    }

    private static func operating(
        label: String,
        threshold: Float,
        higherIsCloser: Bool,
        values: [(Float, Bool)]
    ) -> BenchmarkReport.Operating? {
        guard !values.isEmpty else { return nil }

        var truePositives = 0, falsePositives = 0, falseNegatives = 0
        for (value, isSame) in values {
            let predictedSame = higherIsCloser ? value >= threshold : value <= threshold
            switch (predictedSame, isSame) {
            case (true, true): truePositives += 1
            case (true, false): falsePositives += 1
            case (false, true): falseNegatives += 1
            case (false, false): break
            }
        }

        let precision = ratio(truePositives, truePositives + falsePositives)
        let recall = ratio(truePositives, truePositives + falseNegatives)
        return BenchmarkReport.Operating(
            label: label,
            threshold: threshold,
            precision: precision,
            recall: recall,
            f1Score: precision + recall > 0 ? 2 * precision * recall / (precision + recall) : 0
        )
    }

    private static func ratio(_ numerator: Int, _ denominator: Int) -> Float {
        denominator > 0 ? Float(numerator) / Float(denominator) : 0
    }
}
