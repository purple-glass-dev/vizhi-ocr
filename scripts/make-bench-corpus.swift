#!/usr/bin/env swift
//
// Generates synthetic benchmark samples with perfect ground truth by rendering content we control
// into PNGs. License-free, deterministic, and committable — enough to exercise the harness and
// catch regressions. It also differentiates engines: Apple Vision emits flat text, so on the
// `tables` and `math` samples it can't reconstruct the structure that GLM-OCR can, and the scores
// show it. For real-world scans/handwriting, fetch a public benchmark locally (see
// benchmarks/corpus/README.md and scripts/fetch-bench-corpus.sh).
//
// Usage: swift scripts/make-bench-corpus.swift [output-dir]   (default: benchmarks/corpus)

import AppKit
import Foundation

let outRoot = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "benchmarks/corpus", isDirectory: true)

let margin: CGFloat = 48
let bodyFont = NSFont.systemFont(ofSize: 32, weight: .regular)
let black = NSColor.black

// MARK: - Sample definition

enum Content {
    case text(String)                              // render the string verbatim
    case table(headers: [String], rows: [[String]])
}

struct Sample {
    let category: String
    let name: String
    let content: Content
    let expected: String   // ground-truth Markdown
}

// Build a Markdown table string from headers + rows (the ground truth for table samples).
func markdownTable(headers: [String], rows: [[String]]) -> String {
    var out = "| " + headers.joined(separator: " | ") + " |\n"
    out += "| " + headers.map { _ in "---" }.joined(separator: " | ") + " |\n"
    for row in rows { out += "| " + row.joined(separator: " | ") + " |\n" }
    return out.trimmingCharacters(in: .newlines)
}

let samples: [Sample] = [
    // --- plain: prose / reading order / digits (both engines should nail these) -------------
    Sample(category: "plain", name: "pangram", content: .text("""
        The quick brown fox jumps over the lazy dog.
        Pack my box with five dozen liquor jugs.
        How vexingly quick daft zebras jump!
        """), expected: """
        The quick brown fox jumps over the lazy dog.
        Pack my box with five dozen liquor jugs.
        How vexingly quick daft zebras jump!
        """),
    Sample(category: "plain", name: "paragraph", content: .text("""
        On-device OCR keeps your documents private: nothing is ever uploaded.
        Recognition runs entirely on the Apple Neural Engine and GPU, so a
        screenshot becomes editable text in a moment, even with no network.
        """), expected: """
        On-device OCR keeps your documents private: nothing is ever uploaded.
        Recognition runs entirely on the Apple Neural Engine and GPU, so a
        screenshot becomes editable text in a moment, even with no network.
        """),
    Sample(category: "plain", name: "digits", content: .text("""
        Invoice 2026-0042 — total due 1,289.50 on 2026-07-15.
        Account 4571-8830-2266 routing 021000021 ref #A7Q-93X.
        """), expected: """
        Invoice 2026-0042 — total due 1,289.50 on 2026-07-15.
        Account 4571-8830-2266 routing 021000021 ref #A7Q-93X.
        """),

    // --- math: linear equations with unicode super/subscripts; GT is LaTeX -------------------
    // (math normalization strips $ delimiters, so the engine's delimiter style doesn't matter)
    Sample(category: "math", name: "pythagoras", content: .text("a² + b² = c²"),
           expected: "$$a^2 + b^2 = c^2$$"),
    Sample(category: "math", name: "mass-energy", content: .text("E = mc²"),
           expected: "$$E = mc^2$$"),
    Sample(category: "math", name: "binomial", content: .text("(a + b)² = a² + 2ab + b²"),
           expected: "$$(a + b)^2 = a^2 + 2ab + b^2$$"),

    // --- tables: drawn grids; GT is a Markdown table ----------------------------------------
    Sample(category: "tables", name: "groceries",
           content: .table(headers: ["Item", "Qty", "Price"],
                           rows: [["Apple", "3", "1.50"], ["Bread", "1", "2.20"], ["Milk", "2", "3.10"]]),
           expected: markdownTable(headers: ["Item", "Qty", "Price"],
                                   rows: [["Apple", "3", "1.50"], ["Bread", "1", "2.20"], ["Milk", "2", "3.10"]])),
    Sample(category: "tables", name: "quarters",
           content: .table(headers: ["Quarter", "Revenue", "Growth"],
                           rows: [["Q1", "120", "4%"], ["Q2", "138", "15%"], ["Q3", "151", "9%"]]),
           expected: markdownTable(headers: ["Quarter", "Revenue", "Growth"],
                                   rows: [["Q1", "120", "4%"], ["Q2", "138", "15%"], ["Q3", "151", "9%"]])),
]

// MARK: - Rendering

func attributed(_ text: String) -> NSAttributedString {
    let style = NSMutableParagraphStyle()
    style.lineSpacing = 8
    return NSAttributedString(string: text, attributes: [
        .font: bodyFont, .paragraphStyle: style, .foregroundColor: black,
    ])
}

func bitmap(width: CGFloat, height: CGFloat, draw: (NSSize) -> Void) -> Data {
    let size = NSSize(width: width, height: height)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
    draw(size)
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encoding failed")
    }
    return data
}

func renderText(_ text: String) -> Data {
    let maxWidth: CGFloat = 1000
    let attr = attributed(text)
    let bounds = attr.boundingRect(with: NSSize(width: maxWidth, height: .greatestFiniteMagnitude),
                                   options: [.usesLineFragmentOrigin, .usesFontLeading])
    return bitmap(width: maxWidth + margin * 2, height: ceil(bounds.height) + margin * 2) { size in
        attr.draw(with: NSRect(x: margin, y: margin, width: maxWidth, height: ceil(bounds.height)),
                  options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}

// Draw a real gridded table so the model has to recover structure, not just text.
func renderTable(headers: [String], rows: [[String]]) -> Data {
    let grid = [headers] + rows
    let cols = headers.count
    let colWidth: CGFloat = 280
    let rowHeight: CGFloat = 70
    let tableWidth = colWidth * CGFloat(cols)
    let tableHeight = rowHeight * CGFloat(grid.count)

    return bitmap(width: tableWidth + margin * 2, height: tableHeight + margin * 2) { size in
        // Flip into top-down coordinates so row 0 is at the top.
        let originY = size.height - margin
        NSColor.black.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 2

        for r in 0...grid.count {   // horizontal rules
            let y = originY - CGFloat(r) * rowHeight
            path.move(to: NSPoint(x: margin, y: y))
            path.line(to: NSPoint(x: margin + tableWidth, y: y))
        }
        for c in 0...cols {         // vertical rules
            let x = margin + CGFloat(c) * colWidth
            path.move(to: NSPoint(x: x, y: originY))
            path.line(to: NSPoint(x: x, y: originY - tableHeight))
        }
        path.stroke()

        for (r, row) in grid.enumerated() {
            for (c, cell) in row.enumerated() {
                let bold = r == 0
                let font = bold ? NSFont.boldSystemFont(ofSize: 28) : NSFont.systemFont(ofSize: 28)
                let text = NSAttributedString(string: cell, attributes: [.font: font, .foregroundColor: black])
                let x = margin + CGFloat(c) * colWidth + 16
                let y = originY - CGFloat(r) * rowHeight - rowHeight + 20
                text.draw(at: NSPoint(x: x, y: y))
            }
        }
    }
}

func png(for content: Content) -> Data {
    switch content {
    case .text(let s): renderText(s)
    case .table(let headers, let rows): renderTable(headers: headers, rows: rows)
    }
}

// MARK: - Write

let fm = FileManager.default
for sample in samples {
    let dir = outRoot.appendingPathComponent(sample.category, isDirectory: true)
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let base = dir.appendingPathComponent(sample.name)
    try! png(for: sample.content).write(to: base.appendingPathExtension("png"))
    try! sample.expected.write(to: base.appendingPathExtension("expected.md"),
                               atomically: true, encoding: .utf8)
    print("  + \(sample.category)/\(sample.name)")
}
print("Wrote \(samples.count) synthetic sample(s) to \(outRoot.path)")
