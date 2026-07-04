import Foundation
import Testing
@testable import VizhiBench

@Suite("Scoring")
struct ScoringTests {
    // MARK: Edit distance / metrics

    @Test("Identical text scores zero error")
    func identicalIsPerfect() {
        let r = errorRates(reference: "the quick brown fox", hypothesis: "the quick brown fox")
        #expect(r.cer == 0)
        #expect(r.wer == 0)
    }

    @Test("Both empty is perfect, not NaN")
    func emptyIsPerfect() {
        #expect(errorRates(reference: "", hypothesis: "") == .perfect)
    }

    @Test("One character substitution over five characters is 20% CER")
    func singleCharSubstitution() {
        let r = errorRates(reference: "hello", hypothesis: "hallo")
        #expect(abs(r.cer - 0.2) < 1e-9)
    }

    @Test("One wrong word over four words is 25% WER")
    func singleWordSubstitution() {
        let r = errorRates(reference: "a b c d", hypothesis: "a x c d")
        #expect(abs(r.wer - 0.25) < 1e-9)
    }

    @Test("Totally wrong hypothesis scores near or above 1.0")
    func totallyWrong() {
        let r = errorRates(reference: "abc", hypothesis: "xyz")
        #expect(r.cer >= 1.0)
    }

    // MARK: Normalization profiles

    @Test("Whitespace folds in the prose profile")
    func prosefoldsWhitespace() {
        let n = normalize("the   quick\n\nbrown   fox", with: .prose)
        #expect(n == "the quick brown fox")
    }

    @Test("Prose profile ignores Markdown emphasis")
    func proseIgnoresEmphasis() {
        let scorer = OCRScorer()
        let r = scorer.score(reference: "a **bold** word", hypothesis: "a bold word", category: "plain")
        #expect(r.cer == 0)
    }

    @Test("Table separator rules and pipes drop out under the tables profile")
    func tablesNormalize() {
        let reference = """
        | Name | Qty |
        | --- | --- |
        | Apple | 3 |
        """
        let hypothesis = "Name Qty Apple 3"
        let scorer = OCRScorer()
        let r = scorer.score(reference: reference, hypothesis: hypothesis, category: "tables")
        #expect(r.cer == 0)
    }

    @Test("Math delimiter style doesn't count against the score")
    func mathDelimitersIgnored() {
        let scorer = OCRScorer()
        let r = scorer.score(reference: "$$E = mc^2$$", hypothesis: "\\(E = mc^2\\)", category: "math")
        #expect(r.cer == 0)
    }

    @Test("Unicode superscripts and minus fold to LaTeX form under the math profile")
    func mathSymbolsCanonicalized() {
        let scorer = OCRScorer()
        // Image-faithful unicode reading vs LaTeX ground truth should score identically.
        let r = scorer.score(reference: "$$a^2 + b^2 = c^2$$", hypothesis: "a² + b² = c²", category: "math")
        #expect(r.cer == 0)
        let minus = scorer.score(reference: "$$x = -1$$", hypothesis: "x = −1", category: "math")
        #expect(minus.cer == 0)
    }

    @Test("Braced exponents and cosmetic spacing don't count against math")
    func mathBracesAndSpacingIgnored() {
        let scorer = OCRScorer()
        // GLM-OCR emits `$$ a^{2}+b^{2}=c^{2} $$`; ground truth is `$$a^2 + b^2 = c^2$$`.
        let r = scorer.score(
            reference: "$$a^2 + b^2 = c^2$$",
            hypothesis: "$$\na^{2}+b^{2}=c^{2}\n$$",
            category: "math"
        )
        #expect(r.cer == 0)
    }

    @Test("Unknown category falls back to the prose profile")
    func unknownCategoryUsesProse() {
        #expect(OCRScorer().profile(for: "handwriting") == .prose)
    }
}
