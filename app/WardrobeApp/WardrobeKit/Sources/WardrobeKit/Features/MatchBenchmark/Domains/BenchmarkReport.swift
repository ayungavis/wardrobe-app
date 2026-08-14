import Foundation

/// How cleanly matching separates "same garment" from "different garment" over
/// a set of photos the user labelled by hand.
///
/// The per-signal rows are the whole point. If the feature print alone separates
/// badly while colour alone separates well, the embedding is the weak link and a
/// bigger model is worth its megabytes — if the print already separates well,
/// swapping models buys nothing and the fix is in the thresholds.
struct BenchmarkReport: Equatable, Sendable {
    struct Distribution: Equatable, Sendable {
        let count: Int
        let lowest: Float
        let median: Float
        let highest: Float
    }

    struct Operating: Equatable, Sendable {
        let label: String
        let threshold: Float
        let precision: Float
        let recall: Float
        let f1Score: Float
    }

    struct Signal: Equatable, Sendable {
        let name: String
        /// True when a bigger number means "more likely the same garment".
        let higherIsCloser: Bool
        let same: Distribution?
        let different: Distribution?
        /// The best F1 any single threshold on this signal alone can reach.
        let best: Operating?
        /// Where the thresholds we actually ship sit today.
        let current: [Operating]
    }

    /// One comparison, flattened for printing. Ids only — never anything about
    /// what the photo contains (PRD §18/§24).
    struct Pair: Equatable, Sendable {
        let left: String
        let right: String
        let category: GarmentCategory
        let score: Float
        let colorDelta: Float
        let printDistance: Float?
        let aspectDelta: Float
    }

    let sampleCount: Int
    let groupCount: Int
    let samePairCount: Int
    let differentPairCount: Int
    let signals: [Signal]
    /// Same garment, lowest scores — the merges we would have missed.
    let worstFalseNegatives: [Pair]
    /// Different garments, highest scores — the merges we would have invented.
    let worstFalsePositives: [Pair]
}

// MARK: - Rendering

extension BenchmarkReport {
    /// Plain text, because it has to survive being read on a phone screen and
    /// pasted into a chat.
    var formatted: String {
        ([
            "Samples \(sampleCount) in \(groupCount) garments",
            "Pairs    \(samePairCount) same / \(differentPairCount) different",
            "",
        ] + signals.flatMap(lines(for:)) + worstCaseLines).joined(separator: "\n")
    }

    private func lines(for signal: Signal) -> [String] {
        var lines = ["\(signal.name)  (\(signal.higherIsCloser ? "higher" : "lower") = same)"]
        lines.append("  same      \(describe(signal.same))")
        lines.append("  different \(describe(signal.different))")
        if let best = signal.best {
            lines.append("  best      \(describe(best))")
        }
        lines.append(contentsOf: signal.current.map { "  \(describe($0))" })
        lines.append("")
        return lines
    }

    private var worstCaseLines: [String] {
        var lines: [String] = []
        if !worstFalseNegatives.isEmpty {
            lines.append("Missed merges (same garment, lowest score)")
            lines.append(contentsOf: worstFalseNegatives.map { "  \(describe($0))" })
            lines.append("")
        }
        if !worstFalsePositives.isEmpty {
            lines.append("Invented merges (different garments, highest score)")
            lines.append(contentsOf: worstFalsePositives.map { "  \(describe($0))" })
        }
        return lines
    }

    private func describe(_ distribution: Distribution?) -> String {
        guard let distribution else { return "none" }
        return "n=\(distribution.count) "
            + "min \(number(distribution.lowest)) "
            + "med \(number(distribution.median)) "
            + "max \(number(distribution.highest))"
    }

    private func describe(_ operating: Operating) -> String {
        "\(operating.label) @\(number(operating.threshold)) "
            + "P \(number(operating.precision)) "
            + "R \(number(operating.recall)) "
            + "F1 \(number(operating.f1Score))"
    }

    private func describe(_ pair: Pair) -> String {
        let print = pair.printDistance.map(number) ?? "none"
        return "\(pair.left) vs \(pair.right) \(pair.category.rawValue) "
            + "score \(number(pair.score)) dE \(number(pair.colorDelta)) "
            + "fp \(print) dAsp \(number(pair.aspectDelta))"
    }

    private func number(_ value: Float) -> String {
        value.isFinite ? String(format: "%.3f", value) : "inf"
    }
}
