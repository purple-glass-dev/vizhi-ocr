import CoreGraphics
import Foundation
import ScreenCaptureKit
import VizhiCore

public enum CaptureError: Error, Equatable {
    case notAuthorized
    case displayNotFound
    case emptySelection
    case captureFailed(String)
}

/// Captures a rectangular region of a display as a `CGImage`, ready to hand to an OCR engine.
/// Backed by ScreenCaptureKit. Requires Screen Recording permission; the importer path does not
/// use this type.
public struct ScreenRegionCapturer: Sendable {
    public init() {}

    /// Captures `selectionInGlobal` (AppKit global coordinates) from the display whose frame
    /// contains it. `displayFrame` mirrors `NSScreen.frame` for the target display.
    public func capture(
        selectionInGlobal selection: CGRect,
        display: SCDisplay,
        displayFrame: CGRect,
        scaleFactor: CGFloat
    ) async throws -> OCRImage {
        guard ScreenRecordingPermission.current == .authorized else {
            throw CaptureError.notAuthorized
        }
        guard let crop = RegionGeometry.cropRect(selectionInGlobal: selection, displayFrame: displayFrame) else {
            throw CaptureError.emptySelection
        }

        // Exclude our own windows from the capture. Starting a capture activates the app, which
        // raises any open VizhiOCR window (e.g. the Model Manager) above whatever the user is
        // screenshotting — without this, that window lands in the captured pixels and gets OCR'd.
        let ownWindows = try await ownAppWindows()
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
        let config = SCStreamConfiguration()
        config.sourceRect = crop
        config.width = Int(crop.width * scaleFactor)
        config.height = Int(crop.height * scaleFactor)
        config.showsCursor = false

        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return OCRImage(cgImage: image)
        } catch {
            throw CaptureError.captureFailed(String(describing: error))
        }
    }

    /// The currently shareable windows that belong to this app, so they can be excluded from a
    /// capture. Matched by bundle identifier; empty if none are open.
    private func ownAppWindows() async throws -> [SCWindow] {
        let content = try await SCShareableContent.current
        let ownBundleID = Bundle.main.bundleIdentifier
        return content.windows.filter { $0.owningApplication?.bundleIdentifier == ownBundleID }
    }

    /// Looks up the shareable display whose `displayID` matches, e.g. an `NSScreen`'s
    /// `NSScreenNumber`.
    public func display(withID displayID: CGDirectDisplayID) async throws -> SCDisplay {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }
        return display
    }
}
