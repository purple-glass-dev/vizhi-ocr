import AppKit
import VizhiCapture
import VizhiCore

/// Orchestrates a screen-region capture: shows a dimmed selection overlay on every display, then
/// on selection hides the overlay, captures that display's region via ScreenCaptureKit, and hands
/// the image to the CaptureController. Requires Screen Recording permission; without it, the user
/// is pointed at the always-available Import path.
@MainActor
final class RegionCaptureCoordinator {
    private let controller: CaptureController
    private let capturer = ScreenRegionCapturer()

    /// One overlay window per screen; held for the duration of a selection.
    private var overlayWindows: [OverlayWindow] = []

    init(controller: CaptureController) {
        self.controller = controller
    }

    /// Begins a capture in the given mode, or reports a recoverable message if capture isn't
    /// possible (permission denied, no displays).
    func begin(mode: CaptureMode) {
        guard overlayWindows.isEmpty else { return } // a selection is already in progress

        if ScreenRecordingPermission.current == .denied {
            ScreenRecordingPermission.request()
            guard ScreenRecordingPermission.current == .authorized else {
                controller.report(failure: "Enable Screen Recording in System Settings to capture the screen. You can still drop a file via Import.")
                return
            }
        }

        presentOverlays(mode: mode)
    }

    private func presentOverlays(mode: CaptureMode) {
        for screen in NSScreen.screens {
            let window = OverlayWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.setFrame(screen.frame, display: true)
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

            let view = SelectionOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.onComplete = { [weak self] localRect in
                self?.finish(localRect: localRect, screen: screen, mode: mode)
            }
            view.onCancel = { [weak self] in self?.dismissOverlays() }
            window.contentView = view

            window.makeKeyAndOrderFront(nil)
            overlayWindows.append(window)
        }

        if !overlayWindows.isEmpty {
            NSApp.activate()
            overlayWindows.first?.makeKey()
        }
    }

    private func dismissOverlays() {
        for window in overlayWindows { window.orderOut(nil) }
        overlayWindows.removeAll()
    }

    private func finish(localRect: NSRect, screen: NSScreen, mode: CaptureMode) {
        // The view fills the window, which fills the screen, so view-local (bottom-left) maps to
        // global by offsetting with the screen's origin.
        let globalRect = CGRect(
            x: screen.frame.minX + localRect.minX,
            y: screen.frame.minY + localRect.minY,
            width: localRect.width,
            height: localRect.height
        )
        let displayID = screen.displayID
        let displayFrame = screen.frame
        let scale = screen.backingScaleFactor

        dismissOverlays()
        controller.beginWorking()

        Task {
            do {
                // Let the overlay fully clear before the screenshot so dimming isn't captured.
                try? await Task.sleep(for: .milliseconds(80))
                guard let displayID else { throw CaptureError.displayNotFound }
                let display = try await capturer.display(withID: displayID)
                let image = try await capturer.capture(
                    selectionInGlobal: globalRect,
                    display: display,
                    displayFrame: displayFrame,
                    scaleFactor: scale
                )
                controller.recognize([image], mode: mode)
            } catch {
                controller.report(failure: "Capture failed: \(error)")
            }
        }
    }
}

private extension NSScreen {
    /// The CoreGraphics display id for this screen, used to match an `SCDisplay`.
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
