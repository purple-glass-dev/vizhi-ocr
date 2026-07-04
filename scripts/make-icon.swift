#!/usr/bin/env swift
//
// Renders a 1024×1024 app-icon master PNG: a rounded "app tile" with a blue gradient and the
// app's `text.viewfinder` glyph in white. Run via scripts/make-icon.sh (which slices it into an
// .iconset and builds AppIcon.icns). Swap the colors/symbol here to restyle the icon.
//
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-master.png"
let size: CGFloat = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("could not create bitmap") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Rounded "app tile" with the conventional ~10% padding and ~22% corner radius.
let pad = size * 0.10
let tile = CGRect(x: pad, y: pad, width: size - 2 * pad, height: size - 2 * pad)
let radius = tile.width * 0.225
let path = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)

// Gradient fill (top → bottom).
ctx.saveGState()
ctx.addPath(path)
ctx.clip()
let top = NSColor(srgbRed: 0.22, green: 0.56, blue: 0.96, alpha: 1).cgColor
let bottom = NSColor(srgbRed: 0.09, green: 0.28, blue: 0.69, alpha: 1).cgColor
let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [top, bottom] as CFArray, locations: [0, 1]
)!
ctx.drawLinearGradient(gradient, start: CGPoint(x: tile.minX, y: tile.maxY),
                       end: CGPoint(x: tile.minX, y: tile.minY), options: [])
ctx.restoreGState()

// White `text.viewfinder` glyph, centered.
let config = NSImage.SymbolConfiguration(pointSize: tile.width * 0.5, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let s = symbol.size
    let rect = CGRect(x: tile.midX - s.width / 2, y: tile.midY - s.height / 2, width: s.width, height: s.height)
    symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
}

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png encode failed") }
try! data.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
