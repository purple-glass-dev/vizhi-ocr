import Foundation

/// The two standard OCR accuracy metrics, each in `[0, 1]` (lower is better).
public struct ErrorRates: Sendable, Equatable {
    /// Character Error Rate: edit distance over characters ÷ reference character count.
    public let cer: Double
    /// Word Error Rate: edit distance over whitespace-delimited tokens ÷ reference token count.
    public let wer: Double

    public init(cer: Double, wer: Double) {
        self.cer = cer
        self.wer = wer
    }

    /// A perfect match (used when both strings are empty — no errors over nothing).
    public static let perfect = ErrorRates(cer: 0, wer: 0)
}

/// Computes CER and WER of `hypothesis` against `reference`. Inputs should already be normalized
/// (see `normalize(_:with:)`). The denominator is the reference size, so a totally-wrong hypothesis
/// scores ~1.0 and extra hallucinated text can push a rate above 1.0 (deletions count) — which is
/// intended: it flags engines that pad output.
public func errorRates(reference: String, hypothesis: String) -> ErrorRates {
    if reference.isEmpty && hypothesis.isEmpty { return .perfect }

    let refChars = Array(reference)
    let hypChars = Array(hypothesis)
    let cer = Double(levenshtein(refChars, hypChars)) / Double(max(1, refChars.count))

    let refWords = reference.split(whereSeparator: \.isWhitespace).map(String.init)
    let hypWords = hypothesis.split(whereSeparator: \.isWhitespace).map(String.init)
    let wer = Double(levenshtein(refWords, hypWords)) / Double(max(1, refWords.count))

    return ErrorRates(cer: cer, wer: wer)
}
