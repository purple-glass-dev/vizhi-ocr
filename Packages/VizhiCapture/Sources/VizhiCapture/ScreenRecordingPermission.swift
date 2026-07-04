import CoreGraphics

/// Authorization state for screen capture. The app must work fully without this permission via
/// the drag-drop import path, so callers treat `.denied` as "offer import instead", not a dead end.
public enum ScreenRecordingAuthorization: Sendable, Equatable {
    case authorized
    case denied
}

/// Thin wrapper over the system screen-recording permission. Capture (Fast or AI from the
/// screen) requires `.authorized`; the importer never does.
public enum ScreenRecordingPermission {
    /// Current authorization without prompting.
    public static var current: ScreenRecordingAuthorization {
        CGPreflightScreenCaptureAccess() ? .authorized : .denied
    }

    /// Prompts for access if not yet determined. Returns whether access is granted. Triggers the
    /// system prompt the first time; afterward the user must change it in System Settings.
    @discardableResult
    public static func request() -> ScreenRecordingAuthorization {
        CGRequestScreenCaptureAccess() ? .authorized : .denied
    }
}
