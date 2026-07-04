import Foundation
import Observation

/// Per-model download/installation state, observed by the model-manager UI.
public enum ModelDownloadState: Sendable, Equatable {
    case notInstalled
    case downloading(fraction: Double)
    case verifying
    case installed
    case failed(String)
}

/// Orchestrates downloading a model's files: tries each file's sources in order (Hugging Face,
/// then CDN), verifies checksums, and installs into the model's directory. Observable so SwiftUI
/// reflects progress live. Inject a `FileDownloading` to unit-test the orchestration offline.
@MainActor
@Observable
public final class ModelDownloadManager {
    private let store: ModelStore
    private let downloader: FileDownloading

    /// State by model id. Absent ids are treated as `notInstalled`.
    public private(set) var states: [String: ModelDownloadState] = [:]

    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    public init(store: ModelStore = ModelStore(), downloader: FileDownloading = URLSessionFileDownloader()) {
        self.store = store
        self.downloader = downloader
    }

    public func state(for model: ModelDescriptor) -> ModelDownloadState {
        if states[model.id] == nil, case .installed = store.installState(for: model) {
            return .installed
        }
        return states[model.id] ?? .notInstalled
    }

    /// Starts (or restarts) a download. Idempotent while one is already running for the model.
    public func download(_ model: ModelDescriptor) {
        guard !model.files.isEmpty else {
            states[model.id] = .failed("No download available for this model yet")
            return
        }
        guard tasks[model.id] == nil else { return }
        states[model.id] = .downloading(fraction: 0)
        let task = Task { [weak self] in
            await self?.performDownload(model)
            self?.tasks[model.id] = nil
        }
        tasks[model.id] = task
    }

    public func cancel(_ model: ModelDescriptor) {
        tasks[model.id]?.cancel()
        tasks[model.id] = nil
        states[model.id] = .notInstalled
    }

    /// Deletes an installed model from disk and resets its state.
    public func delete(_ model: ModelDescriptor) throws {
        cancel(model)
        let dir = store.directory(for: model)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
        states[model.id] = .notInstalled
    }

    // MARK: - Internals

    /// Runs the full download+verify+install for a model. Internal (not `private`) so tests can
    /// await it directly instead of polling the fire-and-forget task.
    func performDownload(_ model: ModelDescriptor) async {
        let directory = store.directory(for: model)
        // Weight progress by bytes, not by file count, so the bar tracks real data transferred.
        // Without this a model's many tiny config files race to ~90% while the large weights file
        // (downloaded last) crawls the final stretch. Falls back to file-count weighting when sizes
        // are unknown (all zero).
        let totalBytes = model.totalSizeBytes
        var bytesBefore: Int64 = 0

        do {
            for (index, file) in model.files.enumerated() {
                try Task.checkCancellation()
                let destination = directory.appendingPathComponent(file.name)
                try await downloadFile(
                    file, of: model, to: destination,
                    bytesBefore: bytesBefore, totalBytes: totalBytes,
                    fileIndex: index, fileCount: model.files.count
                )
                bytesBefore += file.sizeBytes
            }
            states[model.id] = .verifying
            try verifyAll(model)
            states[model.id] = .installed
        } catch is CancellationError {
            states[model.id] = .notInstalled
        } catch {
            states[model.id] = .failed(String(describing: error))
        }
    }

    private func downloadFile(
        _ file: ModelFile,
        of model: ModelDescriptor,
        to destination: URL,
        bytesBefore: Int64,
        totalBytes: Int64,
        fileIndex: Int,
        fileCount: Int
    ) async throws {
        let urls = model.source.downloadURLs(forFile: file.name)
        guard !urls.isEmpty else { throw ModelDownloadError.noSourcesConfigured(file: file.name) }

        let modelID = model.id
        var lastError: Error?
        for url in urls {
            do {
                try await downloader.download(from: url, to: destination) { [weak self] fraction in
                    let overall = Self.overallProgress(
                        fileFraction: fraction, bytesBefore: bytesBefore, fileBytes: file.sizeBytes,
                        totalBytes: totalBytes, fileIndex: fileIndex, fileCount: fileCount
                    )
                    Task { @MainActor [weak self] in
                        // Don't clobber a terminal state with a late progress callback.
                        if case .downloading = self?.states[modelID] ?? .downloading(fraction: 0) {
                            self?.states[modelID] = .downloading(fraction: overall)
                        }
                    }
                }
                return // this source succeeded
            } catch {
                lastError = error
                continue // try the next source (CDN fallback)
            }
        }
        throw lastError ?? ModelDownloadError.allSourcesFailed(file: file.name)
    }

    /// Overall download fraction across a model's files. Byte-weighted when sizes are known, so the
    /// bar moves proportionally to data transferred; falls back to equal per-file weighting when the
    /// catalog has no sizes. Pure for unit testing.
    nonisolated static func overallProgress(
        fileFraction: Double,
        bytesBefore: Int64,
        fileBytes: Int64,
        totalBytes: Int64,
        fileIndex: Int,
        fileCount: Int
    ) -> Double {
        if totalBytes > 0 {
            let done = Double(bytesBefore) + fileFraction * Double(fileBytes)
            return min(1, done / Double(totalBytes))
        }
        return (Double(fileIndex) + fileFraction) / Double(max(fileCount, 1))
    }

    private func verifyAll(_ model: ModelDescriptor) throws {
        let directory = store.directory(for: model)
        for file in model.files where !file.sha256.isEmpty {
            let url = directory.appendingPathComponent(file.name)
            guard try Checksum.verify(fileAt: url, matches: file.sha256) else {
                throw ModelDownloadError.checksumMismatch(file: file.name)
            }
        }
    }
}
