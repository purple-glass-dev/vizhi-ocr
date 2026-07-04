import AppKit
import Observation
import VizhiCapture
import VizhiCore
import VizhiMLX
import VizhiModels
import VizhiUI

/// Owns the app's long-lived services and wires global hotkeys to capture. Created once in
/// `VizhiOCRApp` and started from the app delegate, after the app finishes launching so the
/// Carbon event target is ready.
@MainActor
@Observable
final class AppServices {
    static var shared: AppServices?

    let settings: SettingsStore
    let controller: CaptureController
    let regionCapture: RegionCaptureCoordinator
    let downloads = ModelDownloadManager()
    /// Local, opt-in capture history (off by default).
    let history: CaptureHistoryStore
    /// Observable mirror of whether an AI model is resident in memory, for the menubar/import UI.
    let residency = ModelResidency.shared
    /// Floating completion HUD — the feedback for hotkey captures (popover closed).
    private let hud = CaptureHUDController()
    private let hotkeys = CarbonHotkeyManager()

    /// The hotkeys actually registered, so the menu only advertises shortcuts that work.
    private(set) var activeHotkeys: [CaptureAction: Hotkey] = [:]

    /// Opens a SwiftUI window scene by id. Captured from a view (which has `@Environment(\.openWindow)`),
    /// so non-view code like a hotkey capture can route the user to the Model Manager.
    @ObservationIgnored var openWindowAction: ((String) -> Void)?

    @ObservationIgnored private var didOfferOnboarding = false

    /// Shows the first-run welcome window once, the first time the app launches. No-op afterwards.
    func presentOnboardingIfNeeded() {
        guard !didOfferOnboarding, !settings.hasCompletedOnboarding else { return }
        didOfferOnboarding = true
        // Defer to the next runloop tick so the window scenes are registered and openable.
        DispatchQueue.main.async { [weak self] in
            self?.openWindowAction?(WindowID.welcome)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Marks onboarding complete so the welcome window won't appear again.
    func completeOnboarding() {
        settings.hasCompletedOnboarding = true
    }

    init() {
        let settings = SettingsStore()
        let history = CaptureHistoryStore()
        let controller = CaptureController(settings: settings, history: history)
        self.settings = settings
        self.history = history
        self.controller = controller
        self.regionCapture = RegionCaptureCoordinator(controller: controller)
    }

    /// Registers the global hotkeys from the user's settings — both screen captures and Import File.
    func startHotkeys() {
        controller.onNotice = { [weak self] notice in
            guard let self else { return }
            hud.show(notice)
            // Sound only on the terminal result, not while working, informing, or on cancel.
            if settings.playsCompletionSound, notice.kind == .success || notice.kind == .failure {
                CaptureSound.play(isError: notice.kind == .failure)
            }
        }
        controller.onNeedsModelDownload = { [weak self] model in
            guard let self else { return }
            downloads.download(model)              // progress shows in the Model Manager
            openWindowAction?(WindowID.models)     // bring that window up so the user sees it
            NSApp.activate(ignoringOtherApps: true)
        }
        controller.onPreview = { [weak self] in
            guard let self else { return }
            openWindowAction?(WindowID.preview)    // editable review before the result is delivered
            NSApp.activate(ignoringOtherApps: true)
        }
        hotkeys.onTrigger = { [weak self] action in
            guard let self else { return }
            switch action {
            case .fastCapture: regionCapture.begin(mode: .fast)
            case .aiCapture: regionCapture.begin(mode: .ai)
            case .openImport:
                openWindowAction?(WindowID.import)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        reloadHotkeys()
    }

    /// Re-registers the capture hotkeys from current settings. Called on launch and whenever the
    /// user edits a shortcut in Settings.
    func reloadHotkeys() {
        activeHotkeys = settings.hotkeys
        hotkeys.register(activeHotkeys)
    }
}
