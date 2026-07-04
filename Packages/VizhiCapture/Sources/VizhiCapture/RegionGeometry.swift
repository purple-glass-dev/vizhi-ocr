import CoreGraphics

/// Pure geometry for turning a user's drag selection into a crop rect on a specific display.
///
/// Selections arrive in global screen coordinates (AppKit: origin bottom-left, y up). Capture
/// APIs want a rect relative to the display's top-left with y down. This conversion plus clamping
/// is isolated here so it can be unit-tested without any windows or capture permission.
public enum RegionGeometry {
    /// Normalizes a drag between two points into a positive-sized rect.
    public static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    /// Converts a selection in global (bottom-left origin) coordinates into a crop rect relative
    /// to `displayFrame`, in top-left origin coordinates, clamped to the display. Returns `nil`
    /// if the selection doesn't overlap the display or is empty after clamping.
    public static func cropRect(
        selectionInGlobal selection: CGRect,
        displayFrame: CGRect
    ) -> CGRect? {
        let intersection = selection.intersection(displayFrame)
        guard !intersection.isNull, intersection.width >= 1, intersection.height >= 1 else {
            return nil
        }
        // Translate to display-local, then flip y (bottom-left -> top-left).
        let localX = intersection.minX - displayFrame.minX
        let flippedY = displayFrame.maxY - intersection.maxY
        return CGRect(x: localX, y: flippedY, width: intersection.width, height: intersection.height)
    }
}
