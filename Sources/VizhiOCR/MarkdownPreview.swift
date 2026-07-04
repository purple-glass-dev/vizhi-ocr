import Foundation
import MarkdownUI
import SwiftMath
import SwiftUI
import VizhiCore

/// Rendered (read-only) view of parsed Markdown blocks. Runs of text blocks (headings, paragraphs,
/// lists, GFM tables, fenced code) are rendered with MarkdownUI; display-math blocks are typeset
/// natively with SwiftMath. Driven from the editable preview, so it reflects the user's edits.
struct MarkdownPreview: View {
    let blocks: [Block]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case let .markdown(source):
                        Markdown(InlineMath.embed(source))
                            .markdownTheme(previewTheme)
                            .markdownInlineImageProvider(MathInlineImageProvider(isDark: colorScheme == .dark))
                    case let .math(latex):
                        MathView(latex: latex)
                            .frame(maxWidth: .infinity, alignment: .center)
                            // Display equations get extra breathing room, as in a real Markdown viewer.
                            .padding(.vertical, 10)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .textSelection(.enabled)
        }
        // Re-rasterize inline math (cached by URL) when the appearance flips, so it recolors.
        .id(colorScheme)
    }

    /// GitHub theme's generous vertical rhythm (paragraph/heading/list margins, line spacing), but
    /// with the adaptive label color and no painted text background so it blends with the window.
    private var previewTheme: Theme {
        Theme.gitHub.text {
            ForegroundColor(Color.primary)
            FontSize(15)
        }
    }

    /// A renderable run: either a chunk of Markdown source or a single display-math equation.
    private enum Segment {
        case markdown(String)
        case math(String)
    }

    /// Splits the blocks into renderable segments, coalescing consecutive non-math blocks into one
    /// Markdown chunk (so MarkdownUI sees full context for spacing/lists) and pulling each math
    /// block out for SwiftMath.
    private var segments: [Segment] {
        var result: [Segment] = []
        var buffer: [Block] = []

        func flush() {
            guard !buffer.isEmpty else { return }
            result.append(.markdown(MarkdownRenderer().render(OCRDocument(blocks: buffer))))
            buffer.removeAll()
        }

        for block in blocks {
            if case let .mathBlock(latex) = block {
                flush()
                result.append(.math(latex))
            } else {
                buffer.append(block)
            }
        }
        flush()
        return result
    }
}

/// Typesets a LaTeX equation with SwiftMath's `MTMathUILabel`, sized to its content and tinted to
/// the system label color so it tracks light/dark appearance.
private struct MathView: NSViewRepresentable {
    let latex: String

    func makeNSView(context: Context) -> MTMathUILabel {
        let label = MTMathUILabel()
        label.labelMode = .display
        label.textAlignment = .center
        label.fontSize = 18
        label.contentInsets = MTEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        configure(label)
        return label
    }

    func updateNSView(_ nsView: MTMathUILabel, context: Context) {
        configure(nsView)
    }

    /// Report the label's true height (and take the proposed width so display math centers) so
    /// SwiftUI reserves enough vertical space — otherwise the centered equation overflows its frame
    /// and overlaps the block above it.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MTMathUILabel, context: Context) -> CGSize? {
        let intrinsic = nsView.intrinsicContentSize
        return CGSize(width: proposal.width ?? intrinsic.width, height: intrinsic.height)
    }

    private func configure(_ label: MTMathUILabel) {
        label.latex = latex
        label.textColor = .labelColor
    }
}

/// Rewrites inline `$…$` math into Markdown inline images (`![](math:<encoded>)`) so MarkdownUI
/// lays them out in the text flow (with wrapping) via `MathInlineImageProvider`.
enum InlineMath {
    /// Pandoc-style inline-math match: a `$` not escaped or doubled and not followed by whitespace,
    /// up to a `$` not preceded by whitespace and not followed by a digit. The digit guard keeps
    /// currency like "$5 and $10" from being read as math.
    private static let regex = try! NSRegularExpression(
        pattern: #"(?<![\\$])\$(?!\s)([^$\n]+?)(?<!\s)\$(?!\d)"#
    )

    static func embed(_ markdown: String) -> String {
        let ns = markdown as NSString
        let matches = regex.matches(in: markdown, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return markdown }

        var result = ""
        var cursor = 0
        for match in matches {
            let full = match.range
            result += ns.substring(with: NSRange(location: cursor, length: full.location - cursor))
            let latex = ns.substring(with: match.range(at: 1))
            let encoded = latex.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? latex
            result += "![](math:\(encoded))"
            cursor = full.location + full.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    /// Recovers the LaTeX from a `math:<encoded>` inline-image URL.
    static func decode(_ url: URL) -> String {
        let string = url.absoluteString
        let encoded = string.hasPrefix("math:") ? String(string.dropFirst("math:".count)) : string
        return encoded.removingPercentEncoding ?? encoded
    }
}

/// Renders the `math:` inline-image URLs produced by `InlineMath.embed` as typeset equations
/// (SwiftMath, inline `.text` mode), so inline math flows within the paragraph text.
struct MathInlineImageProvider: InlineImageProvider {
    let isDark: Bool

    func image(with url: URL, label: String) async throws -> Image {
        let latex = InlineMath.decode(url)
        let dark = isDark
        return await MainActor.run {
            let color: NSColor = dark ? .white : .black
            let (_, image) = MTMathImage(
                latex: latex,
                fontSize: 16,
                textColor: color,
                labelMode: .text,
                textAlignment: .left
            ).asImage()
            if let image {
                return Image(nsImage: image)
            }
            return Image(systemName: "questionmark.square.dashed")
        }
    }
}
