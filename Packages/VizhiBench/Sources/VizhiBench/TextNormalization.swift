import Foundation

/// How aggressively to canonicalize text before scoring.
///
/// Different document categories need different leniency. Prose should match closely, so we only
/// fold whitespace. Tables and math, by contrast, carry structural markup (`|`, `---`, `$$`, `\,`)
/// that two engines can format differently while both being *correct* — penalizing those
/// differences as character errors would make the score measure formatting, not recognition. Each
/// profile strips exactly the noise that's irrelevant for its category and nothing more.
public struct NormalizationProfile: Sendable, Equatable {
    /// Lowercase everything (case-insensitive comparison).
    public var lowercase: Bool
    /// Collapse runs of whitespace (incl. newlines) to single spaces and trim the ends.
    public var collapseWhitespace: Bool
    /// Remove Markdown emphasis/code markers: `*`, `_`, `` ` `` (the glyphs, not the words).
    public var stripMarkdownEmphasis: Bool
    /// Remove math delimiters so `$x^2$`, `\(x^2\)`, and `$$x^2$$` compare as `x^2`.
    public var stripMathDelimiters: Bool
    /// Fold equivalent math notation to one form so notation choices aren't scored as recognition
    /// errors: unicode super/subscripts → `^n`/`_n`, and the unicode minus `−` → ASCII `-`.
    public var canonicalizeMathSymbols: Bool
    /// Remove *all* whitespace rather than collapsing it. In math, spacing around operators is
    /// cosmetic (`a+b` ≡ `a + b`), so it shouldn't count as a recognition error.
    public var stripAllWhitespace: Bool
    /// Collapse table markup: drop separator rules (`| --- |`) and pipe/cell padding so only cell
    /// text remains, in reading order.
    public var normalizeTableMarkup: Bool

    public init(
        lowercase: Bool = false,
        collapseWhitespace: Bool = true,
        stripMarkdownEmphasis: Bool = false,
        stripMathDelimiters: Bool = false,
        canonicalizeMathSymbols: Bool = false,
        stripAllWhitespace: Bool = false,
        normalizeTableMarkup: Bool = false
    ) {
        self.lowercase = lowercase
        self.collapseWhitespace = collapseWhitespace
        self.stripMarkdownEmphasis = stripMarkdownEmphasis
        self.stripMathDelimiters = stripMathDelimiters
        self.canonicalizeMathSymbols = canonicalizeMathSymbols
        self.stripAllWhitespace = stripAllWhitespace
        self.normalizeTableMarkup = normalizeTableMarkup
    }

    /// Plain text / paragraphs: compare closely, only folding whitespace.
    public static let prose = NormalizationProfile(stripMarkdownEmphasis: true)

    /// Tables: cell content is what matters, not pipe alignment or separator rules.
    public static let tables = NormalizationProfile(
        stripMarkdownEmphasis: true, normalizeTableMarkup: true
    )

    /// Math: the LaTeX body is what matters, not the delimiter style, unicode-vs-LaTeX notation, or
    /// cosmetic operator spacing.
    public static let math = NormalizationProfile(
        stripMathDelimiters: true, canonicalizeMathSymbols: true, stripAllWhitespace: true
    )
}

/// Maps unicode super/subscript digits to their `^n` / `_n` ASCII forms.
private let superscripts = Dictionary(uniqueKeysWithValues: zip("⁰¹²³⁴⁵⁶⁷⁸⁹", "0123456789"))
private let subscripts = Dictionary(uniqueKeysWithValues: zip("₀₁₂₃₄₅₆₇₈₉", "0123456789"))

/// Applies a `NormalizationProfile` to a string. Pure and deterministic so scoring is reproducible.
public func normalize(_ text: String, with profile: NormalizationProfile) -> String {
    var s = text

    if profile.normalizeTableMarkup {
        // Drop Markdown table separator rows (e.g. `| --- | :---: |`) entirely, then turn the
        // remaining pipes into spaces so cell text survives without alignment noise.
        s = s.replacing(#/(?m)^\s*\|?[\s:|-]*-{2,}[\s:|-]*\|?\s*$/#, with: " ")
        s = s.replacing("|", with: " ")
    }

    if profile.stripMathDelimiters {
        s = s.replacing("$$", with: " ")
        s = s.replacing("$", with: " ")
        s = s.replacing(#/\\[()\[\]]/#, with: " ")   // \( \) \[ \]
    }

    if profile.canonicalizeMathSymbols {
        s = s.replacing("−", with: "-")   // U+2212 minus → ASCII hyphen-minus
        // Fold braced super/subscripts: `x^{2}` and `x^2` are the same exponent. Do this before the
        // unicode pass so everything lands in one `^n` form.
        s = s.replacing(#/([_^])\{([^{}]*)\}/#) { match in "\(match.1)\(match.2)" }
        var folded = ""
        folded.reserveCapacity(s.count)
        for ch in s {
            if let d = superscripts[ch] { folded += "^\(d)" }
            else if let d = subscripts[ch] { folded += "_\(d)" }
            else { folded.append(ch) }
        }
        s = folded
    }

    if profile.stripMarkdownEmphasis {
        s = s.replacing(#/[*_`]/#, with: "")
    }

    if profile.lowercase {
        s = s.lowercased()
    }

    if profile.stripAllWhitespace {
        s = s.replacing(#/\s+/#, with: "")
    } else if profile.collapseWhitespace {
        s = s.replacing(#/\s+/#, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    return s
}
