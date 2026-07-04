import Foundation

/// Renders `[BenchmarkResult]` into a Markdown report: a per-category accuracy matrix (mean CER),
/// a latency column, and a per-item appendix. The matrix is the roadmap's "published quality
/// guidance" deliverable — it's what decides the default model and per-model resolution/prompt
/// tuning.
public struct ReportGenerator: Sendable {
    public init() {}

    public func generate(results: [BenchmarkResult], date: Date = Date()) -> String {
        guard !results.isEmpty else { return "# Vizhi OCR — Benchmark\n\n_No results._\n" }

        // Stable, sorted axes.
        let engines = orderedUnique(results.map(\.engineID))
        let categories = orderedUnique(results.map(\.category))

        var out = "# Vizhi OCR — Benchmark\n\n"
        out += "_Generated \(Self.iso(date)). Lower CER is better (0 = perfect)._\n\n"

        // --- Accuracy matrix: engine × category (mean CER) -----------------------
        out += "## Accuracy — mean CER by category\n\n"
        out += "| Engine | " + categories.joined(separator: " | ") + " | **All** |\n"
        out += "| --- | " + categories.map { _ in "---:" }.joined(separator: " | ") + " | ---: |\n"
        for engine in engines {
            let scored = results.filter { $0.engineID == engine && $0.rates != nil }
            var row = "| \(engine) |"
            for category in categories {
                let cers = scored.filter { $0.category == category }.compactMap { $0.rates?.cer }
                row += " \(Self.pct(mean(cers))) |"
            }
            row += " **\(Self.pct(mean(scored.compactMap { $0.rates?.cer })))** |"
            out += row + "\n"
        }

        // --- Speed: mean recognition latency per engine --------------------------
        out += "\n## Speed — mean recognition time\n\n"
        out += "| Engine | Mean | Items | Failures |\n| --- | ---: | ---: | ---: |\n"
        for engine in engines {
            let all = results.filter { $0.engineID == engine }
            let secs = all.filter { $0.error == nil }.map(\.durationSeconds)
            let failures = all.filter { $0.error != nil }.count
            out += "| \(engine) | \(Self.secs(mean(secs))) | \(all.count) | \(failures) |\n"
        }

        // --- Per-item appendix ---------------------------------------------------
        out += "\n## Per-item CER\n\n"
        out += "| Item | Engine | CER | WER | Time |\n| --- | --- | ---: | ---: | ---: |\n"
        for result in results.sorted(by: { ($0.itemID, $0.engineID) < ($1.itemID, $1.engineID) }) {
            let cer = result.rates.map { Self.pct($0.cer) } ?? "—"
            let wer = result.rates.map { Self.pct($0.wer) } ?? "—"
            let note = result.error.map { " ⚠️ \($0.prefix(60))" } ?? ""
            out += "| \(result.itemID) | \(result.engineID) | \(cer) | \(wer) | \(Self.secs(result.durationSeconds))\(note) |\n"
        }

        return out
    }

    // MARK: - Helpers

    private func mean(_ xs: [Double]) -> Double? {
        xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }

    /// Preserves first-seen order while removing duplicates.
    private func orderedUnique(_ xs: [String]) -> [String] {
        var seen = Set<String>()
        return xs.filter { seen.insert($0).inserted }
    }

    private static func pct(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f%%", value * 100)
    }

    private static func secs(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2fs", value)
    }

    private static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f.string(from: date)
    }
}
