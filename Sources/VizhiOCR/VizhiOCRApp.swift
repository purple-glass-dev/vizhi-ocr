import AppKit
import SwiftUI
import VizhiCore
import VizhiUI

/// Keeps Vizhi OCR a menubar-first agent and registers global hotkeys once the Carbon event
/// target is ready.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppServices.shared?.startHotkeys()
    }
}

/// Lets `CaptureController` read preferences without importing the UI layer's concrete store.
extension SettingsStore: SettingsContext {}

/// Lets `RegionCaptureCoordinator` read the screenshot-saving preferences through an abstraction.
extension SettingsStore: ScreenshotSaveContext {}

/// Lets `CaptureController` record into history through an abstraction, not the concrete store.
extension CaptureHistoryStore: HistoryRecording {}

/// Process entry point. Branches to the offline benchmark harness when launched with
/// `--benchmark …` (it runs in-process so MLX finds the bundled Metal library), otherwise starts
/// the normal menubar app.
@main
enum AppEntry {
    static func main() {
        if BenchmarkCommand.isRequested {
            BenchmarkCommand.run()   // runs the benchmark and exits; never returns
        }
        VizhiOCRApp.main()
    }
}

struct VizhiOCRApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var services: AppServices

    init() {
        let services = AppServices()
        AppServices.shared = services
        _services = State(initialValue: services)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView(
                settings: services.settings,
                controller: services.controller,
                regionCapture: services.regionCapture,
                hotkeys: services.activeHotkeys,
                residency: services.residency
            )
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        Window("Import", id: WindowID.import) {
            ImportWindowView(
                settings: services.settings,
                controller: services.controller,
                residency: services.residency
            )
        }
        .windowResizability(.contentSize)

        Window("Models", id: WindowID.models) {
            ModelManagerWindowView(settings: services.settings, downloads: services.downloads)
        }

        Window("History", id: WindowID.history) {
            HistoryView(history: services.history, isEnabled: services.settings.historyEnabled)
        }

        Window("Review Result", id: WindowID.preview) {
            ResultPreviewView(settings: services.settings, controller: services.controller)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("Welcome", id: WindowID.welcome) {
            WelcomeWindowView(services: services)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("Terms of Service", id: WindowID.terms) {
            TermsView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Settings {
            SettingsView(settings: services.settings) {
                services.reloadHotkeys()
            }
        }
    }
}

enum WindowID {
    static let `import` = "import"
    static let models = "models"
    static let history = "history"
    static let preview = "preview"
    static let welcome = "welcome"
    static let terms = "terms"
}

/// The menubar icon. Renders at launch (always present), so its `.onAppear` is a reliable place to
/// hand `openWindow` to non-view code even before the user first opens the menu.
private struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "text.viewfinder")
            .onAppear {
                AppServices.shared?.openWindowAction = { openWindow(id: $0) }
                AppServices.shared?.presentOnboardingIfNeeded()
            }
    }
}

/// Wraps the first-run welcome so it can mark onboarding complete and close itself on "Get Started".
struct WelcomeWindowView: View {
    let services: AppServices
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        WelcomeView(settings: services.settings) {
            services.completeOnboarding()
            dismissWindow(id: WindowID.welcome)
        }
    }
}
