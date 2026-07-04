import AppKit
import SwiftUI
import VizhiCapture

/// A click-to-record control for a single global shortcut. While recording it installs a local
/// key-down monitor (only active when our Settings window is focused), captures the next valid
/// combo, and writes it back through the binding. Escape cancels; a combo needs a non-shift
/// modifier (⌃/⌥/⌘) so it can't collide with plain typing.
struct HotkeyRecorderView: View {
    @Binding var hotkey: Hotkey
    /// Called after a new shortcut is recorded, so the app can re-register with the system.
    let onChange: () -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording ? stop() : start()
        } label: {
            Text(isRecording ? "Type shortcut…" : hotkey.displayString)
                .font(.body.monospaced())
                .frame(minWidth: 96)
        }
        .buttonStyle(.bordered)
        .tint(isRecording ? .accentColor : nil)
        .help(isRecording ? "Press a shortcut, or Escape to cancel" : "Click to change")
        .onDisappear(perform: stop)
    }

    private func start() {
        guard monitor == nil else { return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handle(event)
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    /// Returns `nil` to swallow the key-down so it never reaches a control (and never beeps).
    private func handle(_ event: NSEvent) -> NSEvent? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Escape with no modifiers cancels recording.
        if event.keyCode == 53, flags.isEmpty {
            stop()
            return nil
        }
        let modifiers = Self.modifiers(from: flags)
        // Require a non-shift modifier so the shortcut can't fire during ordinary typing.
        guard !modifiers.intersection([.control, .option, .command]).isEmpty else {
            return nil // keep listening
        }
        hotkey = Hotkey(keyCode: event.keyCode, modifiers: modifiers, keyLabel: Self.label(for: event))
        onChange()
        stop()
        return nil
    }

    nonisolated static func modifiers(from flags: NSEvent.ModifierFlags) -> HotkeyModifiers {
        var result: HotkeyModifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        return result
    }

    /// Human-readable key label for display. Prefers the typed character; falls back to a small
    /// table of common non-printing keys.
    nonisolated static func label(for event: NSEvent) -> String {
        if let chars = event.charactersIgnoringModifiers, let first = chars.first,
           first.isLetter || first.isNumber || first.isPunctuation || first.isSymbol {
            return chars.uppercased()
        }
        return specialKeys[event.keyCode] ?? "Key \(event.keyCode)"
    }

    private nonisolated static let specialKeys: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}
