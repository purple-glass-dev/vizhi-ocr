/// Scores an OCR hypothesis against ground truth, picking the normalization profile that fits the
/// document category so each category is judged on what it should be judged on (see
/// `NormalizationProfile`).
public struct OCRScorer: Sendable {
    public init() {}

    /// The normalization profile for a corpus category (the corpus subfolder name). Unknown
    /// categories fall back to the prose profile.
    public func profile(for category: String) -> NormalizationProfile {
        switch category.lowercased() {
        case "tables", "table": .tables
        case "math", "equations": .math
        default: .prose   // plain, multicolumn, handwriting, reading-order, …
        }
    }

    /// Normalize both sides with the category's profile, then compute CER/WER.
    public func score(reference: String, hypothesis: String, category: String) -> ErrorRates {
        let p = profile(for: category)
        return errorRates(
            reference: normalize(reference, with: p),
            hypothesis: normalize(hypothesis, with: p)
        )
    }
}
