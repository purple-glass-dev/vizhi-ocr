import AppKit
import SwiftUI
import VizhiCapture
import VizhiCore

/// Callbacks the menubar surface invokes. The app wires these to capture/import/quit so this
/// package stays free of engine and lifecycle dependencies.
@MainActor
public struct MenuBarActions {
    public var capture: (CaptureMode) -> Void
    public var openImport: () -> Void
    public var openModelManager: () -> Void
    public var openHistory: () -> Void
    public var openWelcome: () -> Void
    public var quit: () -> Void

    public init(
        capture: @escaping (CaptureMode) -> Void,
        openImport: @escaping () -> Void,
        openModelManager: @escaping () -> Void,
        openHistory: @escaping () -> Void,
        openWelcome: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        self.capture = capture
        self.openImport = openImport
        self.openModelManager = openModelManager
        self.openHistory = openHistory
        self.openWelcome = openWelcome
        self.quit = quit
    }
}

/// Content of the menubar popover: quick capture actions plus entry points to the windows.
public struct MenuBarContentView: View {
    private let actions: MenuBarActions
    private let hotkeys: [CaptureAction: Hotkey]

    public init(actions: MenuBarActions, hotkeys: [CaptureAction: Hotkey] = Hotkey.defaults()) {
        self.actions = actions
        self.hotkeys = hotkeys
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { actions.capture(.fast) } label: {
                row("Capture Text (Fast)", systemImage: "bolt", shortcut: hotkeys[.fastCapture]?.displayString)
            }
            Button { actions.capture(.ai) } label: {
                row("Capture Text (AI)", systemImage: "sparkles", shortcut: hotkeys[.aiCapture]?.displayString)
            }
            Button { dismissing(actions.openImport) } label: {
                row("Import File…", systemImage: "doc.viewfinder", shortcut: hotkeys[.openImport]?.displayString)
            }
            Divider().padding(.vertical, 4)
            Button { dismissing(actions.openModelManager) } label: { row("Manage Models…", systemImage: "cpu") }
            Button { dismissing(actions.openHistory) } label: { row("History…", systemImage: "clock.arrow.circlepath") }
            // Opening the Settings scene must go through SettingsLink on macOS 14+. As a menubar
            // `.accessory` app we don't auto-activate, so without this the Settings window opens
            // behind other apps. Activate alongside the link's own action so it comes to the front.
            SettingsLink { row("Settings…", systemImage: "gearshape") }
                .simultaneousGesture(TapGesture().onEnded { activateApp(); dismissMenuBarExtra() })
            Button { dismissing(actions.openWelcome) } label: { row("Getting Started…", systemImage: "questionmark.circle") }
            Divider().padding(.vertical, 4)
            Button { actions.quit() } label: { row("Quit Vizhi OCR", systemImage: "power") }
        }
        .buttonStyle(.plain)
        .padding(8)
        .frame(width: 260)
    }

    /// Runs a window-opening action and then dismisses the menubar popover, matching native `NSMenu`
    /// behavior where choosing a command closes the menu. The window-style `MenuBarExtra` has no
    /// public dismiss API and stays open on its own, so we close it ourselves.
    private func dismissing(_ action: @escaping () -> Void) {
        action()
        dismissMenuBarExtra()
    }

    /// Closes the window-style `MenuBarExtra` by toggling its status-item button — clicking the icon
    /// while the popover is open closes it. Deferred a tick so it runs after the action's own
    /// window-opening/activation settles, with the popover still in its open state to toggle off.
    ///
    /// Only call this from items that leave the popover open (the window openers). The toggle is not
    /// idempotent: invoking it once the popover has already closed would reopen it, which is why the
    /// self-dismissing capture actions and the terminating Quit item don't use it.
    private func dismissMenuBarExtra() {
        NSApplication.dismissMenuBarExtra()
    }

    /// Brings the app (and the just-opened Settings window) to the front. Fired immediately and once
    /// more after a beat, since the window is created asynchronously by `SettingsLink`.
    private func activateApp() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func row(_ title: String, systemImage: String, shortcut: String? = nil) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            if let shortcut {
                Text(shortcut).foregroundStyle(.secondary).font(.callout)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
    }
}

public extension NSApplication {
    /// Closes the window-style `MenuBarExtra` by toggling its status-item button — clicking the icon
    /// while the popover is open closes it. Deferred a tick so it runs after any window-opening or
    /// activation the caller kicked off settles, with the popover still open to toggle off. Only call
    /// from items that leave the popover open (window openers); the toggle is not idempotent.
    @MainActor
    static func dismissMenuBarExtra() {
        DispatchQueue.main.async {
            NSApp.menuBarExtraStatusButton?.performClick(nil)
        }
    }

    /// The `MenuBarExtra`'s status-item button. SwiftUI doesn't expose the underlying `NSStatusItem`,
    /// so we find its public `NSStatusBarButton` by walking the app's window hierarchies. The button
    /// is the only one of its class, hosted in the status-bar window.
    var menuBarExtraStatusButton: NSStatusBarButton? {
        for window in windows {
            if let button = window.contentView.flatMap(Self.firstStatusBarButton(in:)) {
                return button
            }
        }
        return nil
    }

    static func firstStatusBarButton(in view: NSView) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = firstStatusBarButton(in: subview) { return button }
        }
        return nil
    }
}
