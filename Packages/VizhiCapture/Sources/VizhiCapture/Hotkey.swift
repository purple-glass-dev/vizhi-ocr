/// Modifier keys for a global shortcut.
public struct HotkeyModifiers: OptionSet, Sendable, Codable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let command = HotkeyModifiers(rawValue: 1 << 0)
    public static let option = HotkeyModifiers(rawValue: 1 << 1)
    public static let control = HotkeyModifiers(rawValue: 1 << 2)
    public static let shift = HotkeyModifiers(rawValue: 1 << 3)

    /// macOS-style glyphs, in the conventional ⌃⌥⇧⌘ order.
    public var symbols: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }
}

/// A global shortcut: a virtual key code plus modifiers. Key code maps to Carbon/AppKit virtual
/// keys at registration time.
public struct Hotkey: Sendable, Codable, Hashable {
    public var keyCode: UInt16
    public var modifiers: HotkeyModifiers
    /// Human-readable key label, e.g. "2" or "Space", for display only.
    public var keyLabel: String

    public init(keyCode: UInt16, modifiers: HotkeyModifiers, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    /// Display form like "⇧⌘2".
    public var displayString: String {
        modifiers.symbols + keyLabel
    }
}

/// Actions a global hotkey can trigger.
public enum CaptureAction: String, Sendable, CaseIterable, Codable {
    case fastCapture
    case aiCapture
    case openImport
}

public extension Hotkey {
    /// Suggested defaults using ⌃⌥ to avoid macOS's ⇧⌘3/4/5 screenshot shortcuts: ⌃⌥2 (fast),
    /// ⌃⌥3 (AI), ⌃⌥4 (import). Key codes are AppKit virtual keys.
    static func defaults() -> [CaptureAction: Hotkey] {
        Dictionary(uniqueKeysWithValues: CaptureAction.allCases.map { ($0, defaultHotkey(for: $0)) })
    }

    /// The factory-default shortcut for an action. Non-optional so callers can fall back without a
    /// force-unwrap when resetting or filling gaps for a newly added action.
    static func defaultHotkey(for action: CaptureAction) -> Hotkey {
        switch action {
        case .fastCapture: Hotkey(keyCode: 19, modifiers: [.control, .option], keyLabel: "2")
        case .aiCapture: Hotkey(keyCode: 20, modifiers: [.control, .option], keyLabel: "3")
        case .openImport: Hotkey(keyCode: 21, modifiers: [.control, .option], keyLabel: "4")
        }
    }
}

/// Registers global hotkeys and reports activations. The concrete Carbon/AppKit implementation
/// lives in the app layer; abstracting it keeps this package testable and the registration
/// backend swappable.
public protocol HotkeyRegistering: Sendable {
    func register(_ hotkey: Hotkey, action: CaptureAction) throws
    func unregisterAll()
}
