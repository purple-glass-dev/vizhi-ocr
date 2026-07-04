import AppKit

/// Borderless full-screen window that hosts the selection view. Overridden so it can become key
/// and receive the Escape key to cancel.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Full-screen dimmed view: drag to carve out a clear selection rectangle. Reports the selected
/// rect (in view/local coordinates, bottom-left origin) on mouse-up, or cancels on Escape / a
/// zero-size drag.
final class SelectionOverlayView: NSView {
    var onComplete: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: NSPoint?
    private var selection: NSRect = .zero

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        selection = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        selection = Self.rect(from: start, to: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = startPoint else { return }
        let rect = Self.rect(from: start, to: convert(event.locationInWindow, from: nil))
        startPoint = nil
        if rect.width >= 3, rect.height >= 3 {
            onComplete?(rect)
        } else {
            onCancel?()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()

        guard selection != .zero else { return }

        // Punch the selection clear so the live screen shows through undimmed.
        if let context = NSGraphicsContext.current {
            context.compositingOperation = .copy
            NSColor.clear.setFill()
            selection.fill()
            context.compositingOperation = .sourceOver
        }

        let border = NSBezierPath(rect: selection)
        border.lineWidth = 1
        NSColor.white.setStroke()
        border.stroke()

        drawDimensionLabel()
    }

    private func drawDimensionLabel() {
        let text = "\(Int(selection.width)) × \(Int(selection.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        let padding: CGFloat = 6
        let boxSize = NSSize(width: size.width + padding * 2, height: size.height + padding)
        var origin = NSPoint(x: selection.minX, y: selection.maxY + 6)
        if origin.y + boxSize.height > bounds.maxY { origin.y = selection.minY - boxSize.height - 6 }

        let box = NSRect(origin: origin, size: boxSize)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        text.draw(at: NSPoint(x: box.minX + padding, y: box.minY + padding / 2), withAttributes: attributes)
    }

    static func rect(from start: NSPoint, to end: NSPoint) -> NSRect {
        NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}
