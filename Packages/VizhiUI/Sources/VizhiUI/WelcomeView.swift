import SwiftUI
import VizhiCapture

/// First-run welcome: what the app does, the capture shortcuts, the privacy promise, and an optional
/// Screen Recording grant. Import always works without that permission, so onboarding never blocks.
public struct WelcomeView: View {
    @Bindable private var settings: SettingsStore
    private let onGetStarted: () -> Void

    @State private var screenAuthorized = ScreenRecordingPermission.current == .authorized

    public init(settings: SettingsStore, onGetStarted: @escaping () -> Void) {
        self._settings = Bindable(settings)
        self.onGetStarted = onGetStarted
    }

    public var body: some View {
        VStack(spacing: 18) {
            header
            VStack(alignment: .leading, spacing: 14) {
                feature("bolt.fill", "Instant capture",
                        "Press \(fastShortcut) to grab text, \(aiShortcut) for AI on tables, math & handwriting.")
                feature("doc.viewfinder", "Drag, drop, or pick a file",
                        "Drop a PDF or image (or use “Choose File…”). Works even without Screen Recording.")
                feature("lock.fill", "Private by design",
                        "Everything runs on your Mac. Nothing is ever uploaded.")
                feature("cpu", "On-device AI models",
                        "AI mode downloads a model once in Manage Models, then runs fully offline.")
            }
            permissionCard
            Spacer(minLength: 0)
            Button(action: onGetStarted) {
                Text("Get Started").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(width: 460, height: 560)
        .onAppear { refresh() }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 44)).foregroundStyle(.tint)
            Text("Welcome to Vizhi OCR").font(.title.bold())
            Text("Grab text from anywhere on your Mac — fully on-device.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private func feature(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(.tint).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var permissionCard: some View {
        HStack(spacing: 12) {
            Image(systemName: screenAuthorized ? "checkmark.circle.fill" : "rectangle.dashed.badge.record")
                .font(.title2)
                .foregroundStyle(screenAuthorized ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Screen Recording").font(.subheadline.weight(.medium))
                Text(screenAuthorized
                     ? "Enabled — screen-region capture is ready."
                     : "Needed for screen-region capture. You may need to relaunch after granting.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if !screenAuthorized {
                Button("Grant…") {
                    _ = ScreenRecordingPermission.request()
                    refresh()
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }

    private func refresh() {
        screenAuthorized = ScreenRecordingPermission.current == .authorized
    }

    private var fastShortcut: String { settings.hotkeys[.fastCapture]?.displayString ?? "⌃⌥2" }
    private var aiShortcut: String { settings.hotkeys[.aiCapture]?.displayString ?? "⌃⌥3" }
}
