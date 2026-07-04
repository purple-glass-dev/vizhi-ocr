import Foundation
import Observation
import VizhiCore

/// Local, opt-in capture history. Persists recent results to a JSON file under Application Support
/// and exposes them to the history window. Recording happens only when the user enables history in
/// Settings (the caller gates that); this store just holds and persists what it's given. Local-only,
/// never synced — see docs/PRIVACY.md. Inject a `fileURL` in tests.
@MainActor
@Observable
public final class CaptureHistoryStore {
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let maxEntries: Int

    /// Most-recent-first.
    public private(set) var entries: [HistoryEntry] = []

    public init(fileURL: URL? = nil, maxEntries: Int = 200) {
        self.maxEntries = maxEntries
        self.fileURL = fileURL ?? Self.defaultURL
        self.entries = Self.load(from: self.fileURL)
    }

    /// `~/Library/Application Support/VizhiOCR/history.json`.
    public static var defaultURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("VizhiOCR", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    public func add(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
        persist()
    }

    public func remove(_ id: HistoryEntry.ID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    /// Clears all history and deletes the on-disk file — the privacy "clear all".
    public func clear() {
        entries.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // History is best-effort; a persistence failure must never break a capture.
        }
    }

    private static func load(from url: URL) -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data)
        else { return [] }
        return decoded
    }
}
