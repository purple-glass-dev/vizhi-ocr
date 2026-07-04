import AppKit
import SwiftUI
import VizhiCapture
import VizhiCore
import VizhiMLX
import VizhiUI

/// Builds the menubar actions, wiring window-opening and capture into the shared controller.
struct MenuBarRootView: View {
    let settings: SettingsStore
    let controller: CaptureController
    let regionCapture: RegionCaptureCoordinator
    let hotkeys: [CaptureAction: Hotkey]
    @Bindable var residency: ModelResidency

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            MenuBarContentView(actions: actions, hotkeys: hotkeys)
            Divider()
            residencyFooter
            statusFooter
            if controller.isBusy { stopButton }
            Divider()
            versionFooter
        }
        // Hand the window-opening action to non-view code (e.g. a hotkey capture that needs to open
        // the Model Manager for a first-run download).
        .onAppear { AppServices.shared?.openWindowAction = { openWindow(id: $0) } }
    }

    /// Aborts an in-flight capture from the menubar.
    private var stopButton: some View {
        Button(role: .destructive) { controller.cancel() } label: {
            Label("Stop", systemImage: "stop.circle")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    /// Always-visible line telling the user whether an AI model is in memory.
    private var residencyFooter: some View {
        Label(residency.state.label, systemImage: residency.state.systemImage)
            .font(.caption)
            .foregroundStyle(residency.state.isResident ? .primary : .secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
    }

    /// Build identifier so the user can tell which version/commit is running, plus a small link to the
    /// Terms of Service governing the binary.
    private var versionFooter: some View {
        HStack(spacing: 0) {
            Label(AppVersion.display, systemImage: "tag")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button("Terms of Service") {
                open(WindowID.terms)
                NSApplication.dismissMenuBarExtra()
            }
            .buttonStyle(.link)
            .font(.caption2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private var actions: MenuBarActions {
        MenuBarActions(
            capture: { mode in capture(mode) },
            openImport: { open(WindowID.import) },
            openModelManager: { open(WindowID.models) },
            openHistory: { open(WindowID.history) },
            openWelcome: { open(WindowID.welcome) },
            quit: { NSApp.terminate(nil) }
        )
    }

    /// Opens a window and brings the app forward. As a menubar `.accessory` app we have no Dock
    /// icon, so without activating, opened windows appear behind other apps and look like nothing
    /// happened.
    private func open(_ id: String) {
        openWindow(id: id)
        NSApp.activate()
    }

    @ViewBuilder
    private var statusFooter: some View {
        switch controller.status {
        case .idle:
            EmptyView()
        case .working:
            footerLabel("Recognizing…", systemImage: "hourglass")
        case let .loadingModel(fraction):
            footerLabel("Loading model… \(Int((fraction * 100).rounded()))%", systemImage: "arrow.down.circle")
        case let .recognizing(page, pageCount, tokens):
            footerLabel(
                CaptureController.recognizingLabel(page: page, pageCount: pageCount, tokens: tokens),
                systemImage: "text.viewfinder"
            )
        case .finished:
            // The persistent "copied N blocks → file.md" line is intentionally not shown in the
            // menu: the menu surfaces model residency, not the last clipboard/file result.
            EmptyView()
        case let .failed(message):
            footerLabel(message, systemImage: "exclamationmark.triangle")
        }
    }

    private func footerLabel(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
    }

    /// Starts a screen-region capture: dismiss the menubar popover, then show the drag-select
    /// overlay. Permission handling and capture live in the coordinator.
    private func capture(_ mode: CaptureMode) {
        regionCapture.begin(mode: mode)
    }
}
