import Dispatch
import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXVLM
import Tokenizers

/// Loads and caches the active VLM model container so repeated captures don't pay the (expensive)
/// model load or first-run download again. Actor-isolated for safe reuse.
///
/// **One model resident at a time.** Switching to a different model evicts the previous one — this
/// keeps memory bounded and makes the residency indicator unambiguous (it always names the model
/// that will actually run). The resident model is also released after `idleTimeout` of inactivity
/// (re-armed on every use) and immediately under system memory pressure. Residency transitions are
/// mirrored to `ModelResidency.shared` for the UI.
actor MLXModelCache {
    static let shared = MLXModelCache()

    /// Release the resident model after this much inactivity. Re-armed on every container access, so
    /// it only fires once captures stop. Generous enough not to interrupt a multi-page run.
    static let idleTimeout: Duration = .seconds(300)

    private var container: ModelContainer?
    /// Identity of the resident model: cache key (directory path or repo id) + display name.
    private var currentKey: String?
    private var residentName: String?
    private var idleTask: Task<Void, Never>?
    private var memorySource: DispatchSourceMemoryPressure?

    private init() {
        // Release the resident model immediately when the system reports memory pressure.
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global())
        source.setEventHandler {
            Task { await MLXModelCache.shared.unloadAll() }
        }
        source.resume()
        memorySource = source
    }

    /// Loads a model that has already been downloaded into `directory` (by our download manager).
    /// No network access — tokenizer and weights come from disk.
    func container(forDirectory directory: URL, displayName: String) async throws -> ModelContainer {
        try await loadIfNeeded(key: directory.path, displayName: displayName) {
            try await VLMModelFactory.shared.loadContainer(
                from: directory,
                using: #huggingFaceTokenizerLoader()
            )
        }
    }

    /// Returns a loaded container for the repo, loading (and downloading on first use) if needed.
    /// `progress` reports download fraction during the initial fetch.
    func container(
        for repo: String,
        displayName: String,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> ModelContainer {
        try await loadIfNeeded(key: repo, displayName: displayName) {
            try await VLMModelFactory.shared.loadContainer(
                from: #hubDownloader(),
                using: #huggingFaceTokenizerLoader(),
                configuration: ModelConfiguration(id: repo)
            ) { downloadProgress in
                progress(downloadProgress.fractionCompleted)
            }
        }
    }

    // MARK: - Residency lifecycle

    /// Returns the resident container if it matches `key`; otherwise evicts whatever's loaded and
    /// loads the requested model. Either way the residency indicator ends up naming this model.
    private func loadIfNeeded(
        key: String,
        displayName: String,
        load: () async throws -> ModelContainer
    ) async throws -> ModelContainer {
        if key == currentKey, let container {
            residentName = displayName
            armIdleTimer()
            await setResidency(.loaded(model: displayName))
            return container
        }
        // A different model (or none) is resident — drop it before loading the new one.
        evictCurrent()
        await setResidency(.loading(model: displayName))
        do {
            let loaded = try await load()
            container = loaded
            currentKey = key
            residentName = displayName
            armIdleTimer()
            await setResidency(.loaded(model: displayName))
            return loaded
        } catch {
            await setResidency(.unloaded)
            throw error
        }
    }

    /// Drops the resident model's references and reclaims GPU/Metal buffers, without touching the
    /// published residency (the caller drives that). Used both for idle/pressure unload and when
    /// switching models.
    private func evictCurrent() {
        guard container != nil else { return }
        container = nil
        currentKey = nil
        residentName = nil
        MLX.Memory.clearCache()
    }

    /// Releases the resident model and publishes the transition. Safe to call repeatedly. Used by
    /// the idle timer and memory-pressure handler.
    func unloadAll() async {
        guard let name = residentName else { return }
        idleTask?.cancel()
        idleTask = nil
        await setResidency(.unloading(model: name))
        evictCurrent()
        await setResidency(.unloaded)
    }

    /// (Re)starts the inactivity countdown. Cancels any pending one so the timer always reflects the
    /// most recent use.
    private func armIdleTimer() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleTimeout)
            guard !Task.isCancelled else { return }
            await self?.unloadAll()
        }
    }

    private func setResidency(_ state: ModelResidencyState) async {
        await MainActor.run { ModelResidency.shared.set(state) }
    }
}
