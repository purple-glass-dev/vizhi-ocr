import AppKit
import SwiftUI

/// A brief, system-style floating HUD shown when a capture finishes (or fails). It's the only
/// feedback for a hotkey capture, where the menubar popover is closed and the result lands silently
/// on the clipboard. A borderless, non-activating panel that fades in near the bottom of the screen
/// and auto-dismisses, never stealing focus or clicks.
@MainActor
final class CaptureHUDController {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    func show(_ notice: CaptureController.CaptureNotice) {
        // A cancellation just clears whatever's showing.
        if notice.kind == .cancelled { dismiss(); return }

        let hosting = NSHostingView(rootView: CaptureHUDView(notice: notice))
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = panel ?? makePanel()
        self.panel = panel
        // If the panel is already up (e.g. working → success), swap content in place rather than
        // fading out and back in, so the amber→green transition doesn't flicker.
        let alreadyVisible = panel.isVisible && panel.alphaValue > 0.9
        panel.contentView = hosting
        panel.setContentSize(size)
        position(panel, size: size)

        if alreadyVisible {
            panel.orderFrontRegardless()
        } else {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                panel.animator().alphaValue = 1
            }
        }

        // The in-progress state persists until the capture resolves; success/failure auto-dismiss.
        if notice.kind == .working {
            dismissTask?.cancel()
            dismissTask = nil
        } else {
            scheduleDismiss()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }

    /// Bottom-center of the active screen, comfortably above the Dock.
    private func position(_ panel: NSPanel, size: NSSize) {
        // main can be nil during a hotkey capture (no key window); fall back to the primary screen.
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 96))
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func dismiss() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // Animation completions run on the main run loop, so hopping back on is sound.
            MainActor.assumeIsolated {
                // A newer show() may have re-raised the panel; only hide it if still faded out.
                guard let panel = self?.panel, panel.alphaValue == 0 else { return }
                panel.orderOut(nil)
            }
        })
    }
}

/// Short system sounds played on capture completion when the user enables the option. A crisp
/// "Pop" for success, "Basso" for failure.
enum CaptureSound {
    static func play(isError: Bool) {
        NSSound(named: isError ? "Basso" : "Pop")?.play()
    }
}

/// The HUD's content: an SF Symbol + message on a frosted capsule, à la macOS system HUDs. Amber
/// pulsing hourglass while recognizing; green check on success; red triangle on failure.
private struct CaptureHUDView: View {
    let notice: CaptureController.CaptureNotice

    var body: some View {
        HStack(spacing: 10) {
            icon
                .font(.title2)
                .foregroundStyle(tint)
            Text(notice.message)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .frame(maxWidth: 360)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.08)))
        .fixedSize()
    }

    @ViewBuilder
    private var icon: some View {
        switch notice.kind {
        case .working:
            Image(systemName: "hourglass").symbolEffect(.pulse, options: .repeating)
        case .success:
            Image(systemName: "checkmark.circle.fill")
        case .failure:
            Image(systemName: "exclamationmark.triangle.fill")
        case .info:
            Image(systemName: "arrow.down.circle")
        case .cancelled:
            EmptyView()
        }
    }

    private var tint: Color {
        switch notice.kind {
        case .working: .orange
        case .success: .green
        case .failure: .red
        case .info: .blue
        case .cancelled: .secondary
        }
    }
}
