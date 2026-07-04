/// Where a recognized result is delivered. The clipboard uses the chosen `OutputFormat`; a saved
/// file is always Markdown (`.md`).
public enum OutputDestination: String, Sendable, CaseIterable, Identifiable {
    case clipboard
    case file
    case both

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .clipboard: "Clipboard"
        case .file: "Markdown file"
        case .both: "Clipboard + file"
        }
    }

    public var savesToClipboard: Bool {
        self == .clipboard || self == .both
    }

    public var savesToFile: Bool {
        self == .file || self == .both
    }
}
