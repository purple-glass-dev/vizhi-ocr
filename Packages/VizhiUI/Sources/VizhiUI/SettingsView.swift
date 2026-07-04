import AppKit
import SwiftUI
import VizhiCapture
import VizhiCore

/// Preferences window: default capture mode, output format/destination, global shortcuts, and the
/// history opt-in.
public struct SettingsView: View {
    @Bindable private var settings: SettingsStore
    /// Invoked when a shortcut changes so the app can re-register hotkeys with the system.
    private let onHotkeysChanged: () -> Void

    public init(settings: SettingsStore, onHotkeysChanged: @escaping () -> Void = {}) {
        self._settings = Bindable(settings)
        self.onHotkeysChanged = onHotkeysChanged
    }

    public var body: some View {
        Form {
            Section("Capture") {
                Picker("Default mode", selection: $settings.defaultMode) {
                    Text("Fast (Apple Vision)").tag(CaptureMode.fast)
                    Text("AI (on-device model)").tag(CaptureMode.ai)
                }
                Toggle("Play a sound when a capture completes", isOn: $settings.playsCompletionSound)
                Toggle("Launch at startup", isOn: $settings.launchAtLogin)
            }
            Section("Output") {
                Picker("Copy as", selection: $settings.outputFormat) {
                    ForEach(OutputFormat.generalCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                Text("CSV and JSON are offered per-capture in the preview when a table is detected.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Preview & edit before copying", isOn: $settings.previewBeforeCopy)
                Picker("Send to", selection: $settings.outputDestination) {
                    ForEach(OutputDestination.allCases) { destination in
                        Text(destination.displayName).tag(destination)
                    }
                }
                if settings.outputDestination.savesToFile {
                    HStack {
                        Text("Save folder").foregroundStyle(.secondary)
                        Spacer()
                        Text(settings.saveFolderURL.lastPathComponent).foregroundStyle(.secondary)
                        Button("Choose…") { chooseFolder() }
                    }
                    Text("Saved files are Markdown (.md), or the format you pick in the preview.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Shortcuts") {
                shortcutRow("Capture Text (Fast)", action: .fastCapture)
                shortcutRow("Capture Text (AI)", action: .aiCapture)
                shortcutRow("Import File…", action: .openImport)
                HStack {
                    Text("Use ⌃, ⌥, or ⌘ with a key. Escape cancels.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset to Defaults", action: resetHotkeys)
                        .controlSize(.small)
                }
            }
            Section("Privacy") {
                Toggle("Keep a local capture history", isOn: $settings.historyEnabled)
                Text("History never leaves your Mac. Off by default.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 480)
    }

    private func shortcutRow(_ title: String, action: CaptureAction) -> some View {
        LabeledContent(title) {
            HotkeyRecorderView(hotkey: hotkeyBinding(action), onChange: onHotkeysChanged)
        }
    }

    /// Binds one action's shortcut, falling back to the factory default if it is somehow missing.
    private func hotkeyBinding(_ action: CaptureAction) -> Binding<Hotkey> {
        Binding(
            get: { settings.hotkeys[action] ?? Hotkey.defaultHotkey(for: action) },
            set: { settings.hotkeys[action] = $0 }
        )
    }

    private func resetHotkeys() {
        settings.hotkeys = Hotkey.defaults()
        onHotkeysChanged()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.saveFolderURL
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveFolderURL = url
        }
    }
}
