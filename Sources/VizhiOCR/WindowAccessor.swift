import AppKit
import SwiftUI

/// Bridges a SwiftUI scene to its hosting `NSWindow` so AppKit-level window behavior can be applied
/// (a SwiftUI `Window` doesn't expose this directly). The closure runs once the view is attached to
/// a window, and again on updates; keep it idempotent.
struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            if let window = view?.window { configure(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            if let window = nsView?.window { configure(window) }
        }
    }
}
