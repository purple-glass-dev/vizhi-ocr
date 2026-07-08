import AppKit
import Foundation
import Testing
@testable import VizhiUI
import VizhiCapture
import VizhiCore
import VizhiModels

@Suite("Settings persistence")
struct SettingsStoreTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Defaults to Fast mode, Markdown, clipboard, history off")
    func defaultsValues() {
        let store = SettingsStore(defaults: freshDefaults())
        #expect(store.defaultMode == .fast)
        #expect(store.outputFormat == .markdown)
        #expect(store.historyEnabled == false)
        #expect(store.selectedModelID == nil)
        #expect(store.outputDestination == .clipboard)
        #expect(store.playsCompletionSound == false)
        // Preview & edit is on by default — the useful default for catching a misread.
        #expect(store.previewBeforeCopy == true)
        #expect(store.hasCompletedOnboarding == false)
        #expect(store.saveScreenshotsEnabled == false)
        #expect(store.screenshotFolderURL == SettingsStore.defaultSaveFolder)
    }

    @Test("Changes persist and reload from the same defaults")
    func persistence() {
        let defaults = freshDefaults()
        let store = SettingsStore(defaults: defaults)
        store.defaultMode = .ai
        store.outputFormat = .plainText
        store.selectedModelID = "glm-ocr-4bit"
        store.historyEnabled = true
        store.outputDestination = .both
        store.saveFolderURL = URL(fileURLWithPath: "/tmp/vizhi-out")
        store.playsCompletionSound = true
        store.previewBeforeCopy = true
        store.hasCompletedOnboarding = true
        store.saveScreenshotsEnabled = true
        store.screenshotFolderURL = URL(fileURLWithPath: "/tmp/vizhi-shots")

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.playsCompletionSound == true)
        #expect(reloaded.previewBeforeCopy == true)
        #expect(reloaded.hasCompletedOnboarding == true)
        #expect(reloaded.defaultMode == .ai)
        #expect(reloaded.outputFormat == .plainText)
        #expect(reloaded.selectedModelID == "glm-ocr-4bit")
        #expect(reloaded.historyEnabled == true)
        #expect(reloaded.outputDestination == .both)
        #expect(reloaded.saveFolderURL.path == "/tmp/vizhi-out")
        #expect(reloaded.saveScreenshotsEnabled == true)
        #expect(reloaded.screenshotFolderURL.path == "/tmp/vizhi-shots")
    }

    @Test("Hotkeys default to the factory shortcuts")
    func hotkeyDefaults() {
        let store = SettingsStore(defaults: freshDefaults())
        #expect(store.hotkeys == Hotkey.defaults())
    }

    @Test("Edited hotkeys persist and reload")
    func hotkeyPersistence() {
        let defaults = freshDefaults()
        let store = SettingsStore(defaults: defaults)
        let custom = Hotkey(keyCode: 5, modifiers: [.command, .shift], keyLabel: "G")
        store.hotkeys[.fastCapture] = custom

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.hotkeys[.fastCapture] == custom)
        // Untouched actions keep their defaults.
        #expect(reloaded.hotkeys[.aiCapture] == Hotkey.defaultHotkey(for: .aiCapture))
    }
}

@Suite("Capture history store")
@MainActor
struct CaptureHistoryStoreTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("vizhi-history-\(UUID().uuidString).json")
    }

    @Test("Adds newest-first and persists across reloads")
    func addAndReload() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = CaptureHistoryStore(fileURL: url)
        store.add(HistoryEntry(engine: "vision", text: "first"))
        store.add(HistoryEntry(engine: "glm", text: "second"))
        #expect(store.entries.map(\.text) == ["second", "first"])

        let reloaded = CaptureHistoryStore(fileURL: url)
        #expect(reloaded.entries.map(\.text) == ["second", "first"])
    }

    @Test("Caps at maxEntries, dropping the oldest")
    func cap() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = CaptureHistoryStore(fileURL: url, maxEntries: 2)
        store.add(HistoryEntry(engine: "e", text: "a"))
        store.add(HistoryEntry(engine: "e", text: "b"))
        store.add(HistoryEntry(engine: "e", text: "c"))
        #expect(store.entries.map(\.text) == ["c", "b"])
    }

    @Test("Clear empties entries and deletes the file")
    func clear() {
        let url = tempURL()
        let store = CaptureHistoryStore(fileURL: url)
        store.add(HistoryEntry(engine: "e", text: "x"))
        #expect(FileManager.default.fileExists(atPath: url.path))
        store.clear()
        #expect(store.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("Preview is the first non-empty line")
    func preview() {
        #expect(HistoryEntry(engine: "e", text: "\n\n  Hello \nworld").preview == "Hello")
        #expect(HistoryEntry(engine: "e", text: "   ").preview == "(empty)")
    }
}

@Suite("Hotkey recorder mapping")
struct HotkeyRecorderTests {
    @Test("Maps AppKit modifier flags to our option set")
    func modifierMapping() {
        #expect(HotkeyRecorderView.modifiers(from: [.control, .option]) == [.control, .option])
        #expect(HotkeyRecorderView.modifiers(from: [.command, .shift]) == [.command, .shift])
        #expect(HotkeyRecorderView.modifiers(from: []) == [])
    }

    @Test("Special keys get glyph labels, others fall back")
    func specialKeyLabels() {
        let space = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.control],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49
        )
        #expect(space.map(HotkeyRecorderView.label(for:)) == "Space")
    }
}

@Suite("Download status presentation")
struct DownloadStatusPresentationTests {
    @Test("Labels reflect state")
    func labels() {
        #expect(DownloadStatusPresentation.label(for: .notInstalled, fallback: "Ready") == "Ready")
        #expect(DownloadStatusPresentation.label(for: .downloading(fraction: 0.5), fallback: "x") == "Downloading… 50%")
        #expect(DownloadStatusPresentation.label(for: .verifying, fallback: "x") == "Verifying…")
        #expect(DownloadStatusPresentation.label(for: .installed, fallback: "x") == "Installed")
        #expect(DownloadStatusPresentation.label(for: .failed("boom"), fallback: "x") == "Failed: boom")
    }

    @Test("Fraction only present while downloading")
    func fraction() {
        #expect(DownloadStatusPresentation.fraction(for: .downloading(fraction: 0.25)) == 0.25)
        #expect(DownloadStatusPresentation.fraction(for: .verifying) == nil)
        #expect(DownloadStatusPresentation.fraction(for: .installed) == nil)
    }

    @Test("Busy during download and verify only")
    func busy() {
        #expect(DownloadStatusPresentation.isBusy(.downloading(fraction: 0.1)))
        #expect(DownloadStatusPresentation.isBusy(.verifying))
        #expect(!DownloadStatusPresentation.isBusy(.installed))
        #expect(!DownloadStatusPresentation.isBusy(.notInstalled))
    }
}

@Suite("Model row presentation")
struct ModelPresentationTests {
    let catalog = ModelCatalog.defaultCatalog

    private func present(_ id: String, ram: Int) -> ModelPresentation {
        let model = catalog.model(id: id)!
        let recommended = ModelTiering().recommendedModel(in: catalog, installedRAMGB: ram)?.id
        return ModelPresentation(
            model: model,
            installedRAMGB: ram,
            installState: .notInstalled,
            recommendedID: recommended
        )
    }

    /// A downloadable model (has a file) at the given RAM thresholds, to exercise fit/comfort
    /// messaging — which only applies to real, downloadable models.
    private func downloadable(minRAM: Int, recommendedRAM: Int, ram: Int) -> ModelPresentation {
        let model = ModelDescriptor(
            id: "dl", displayName: "DL", tier: .standard, capabilities: [.text],
            minRAMGB: minRAM, recommendedRAMGB: recommendedRAM, quantization: "q4",
            source: ModelSource(huggingFaceRepo: "x/y"),
            files: [ModelFile(name: "w.bin", sizeBytes: 1, sha256: "")]
        )
        return ModelPresentation(model: model, installedRAMGB: ram, installState: .notInstalled, recommendedID: nil)
    }

    @Test("Model that exceeds RAM is marked as not fitting")
    func tooBig() {
        let p = downloadable(minRAM: 32, recommendedRAM: 32, ram: 16)
        #expect(p.fits == false)
        #expect(p.statusText == "Needs 32 GB RAM")
    }

    @Test("Downloadable model that fits but lacks headroom warns it's tight")
    func tight() {
        let p = downloadable(minRAM: 16, recommendedRAM: 24, ram: 16)
        #expect(p.fits == true)
        #expect(p.isComfortable == false)
        #expect(p.statusText.contains("24 GB recommended"))
    }

    @Test("Best fit gets the recommended flag")
    func recommended() {
        // 16 GB fits both; the higher-tier 8-bit (Ultra) is recommended.
        #expect(present("glm-ocr-8bit", ram: 16).isRecommended == true)
        #expect(present("glm-ocr-4bit", ram: 16).isRecommended == false)
        // 8 GB only fits the 4-bit.
        #expect(present("glm-ocr-4bit", ram: 8).isRecommended == true)
    }

    @Test("Placeholder model (no files) is not downloadable and is labelled accordingly")
    func placeholderNotDownloadable() {
        let placeholder = ModelDescriptor(
            id: "future", displayName: "Future", tier: .lite, capabilities: [.text],
            minRAMGB: 8, recommendedRAMGB: 8, quantization: "q4",
            source: ModelSource(huggingFaceRepo: "x/y"), files: []
        )
        let p = ModelPresentation(model: placeholder, installedRAMGB: 64, installState: .notInstalled, recommendedID: nil)
        #expect(p.isDownloadable == false)
        #expect(p.statusText == "Not yet available")
    }

    @Test("Catalog GLM-OCR model has real files and is downloadable")
    func realModelDownloadable() {
        let p = present("glm-ocr-4bit", ram: 64)
        #expect(p.isDownloadable == true)
    }

    @Test("Installed model reports installed status")
    func installed() {
        let model = catalog.model(id: "glm-ocr-4bit")!
        let p = ModelPresentation(
            model: model, installedRAMGB: 32,
            installState: .installed(URL(fileURLWithPath: "/tmp/m")),
            recommendedID: nil
        )
        #expect(p.isInstalled)
        #expect(p.statusText == "Installed")
    }
}
