import Foundation
import Testing
@testable import VizhiModels

@Suite("Download URL resolution")
struct DownloadURLTests {
    @Test("Hugging Face is primary, CDN is the fallback")
    func ordering() {
        let source = ModelSource(
            huggingFaceRepo: "org/repo",
            cdnBaseURL: URL(string: "https://cdn.example.com/repo/")
        )
        let urls = source.downloadURLs(forFile: "model.safetensors")
        #expect(urls.map(\.absoluteString) == [
            "https://huggingface.co/org/repo/resolve/main/model.safetensors",
            "https://cdn.example.com/repo/model.safetensors",
        ])
    }

    @Test("Without a CDN, only Hugging Face is offered")
    func hfOnly() {
        let source = ModelSource(huggingFaceRepo: "org/repo")
        #expect(source.downloadURLs(forFile: "f.bin").count == 1)
    }
}

@Suite("Download progress weighting")
struct DownloadProgressTests {
    @Test("Byte-weighted: a tiny file completing barely moves the bar")
    func byteWeighted() {
        // Two files: 100 bytes then 9900 bytes (total 10_000).
        // Finishing the tiny first file is only 1% of the work, not 50%.
        let afterTiny = ModelDownloadManager.overallProgress(
            fileFraction: 1, bytesBefore: 0, fileBytes: 100,
            totalBytes: 10_000, fileIndex: 0, fileCount: 2
        )
        #expect(abs(afterTiny - 0.01) < 0.0001)

        // Halfway through the large second file → 100 + 4950 of 10_000 = ~50.5%.
        let midLarge = ModelDownloadManager.overallProgress(
            fileFraction: 0.5, bytesBefore: 100, fileBytes: 9_900,
            totalBytes: 10_000, fileIndex: 1, fileCount: 2
        )
        #expect(abs(midLarge - 0.505) < 0.0001)
    }

    @Test("Falls back to equal per-file weighting when sizes are unknown")
    func fallback() {
        let p = ModelDownloadManager.overallProgress(
            fileFraction: 0.5, bytesBefore: 0, fileBytes: 0,
            totalBytes: 0, fileIndex: 1, fileCount: 4
        )
        #expect(abs(p - 0.375) < 0.0001) // (1 + 0.5) / 4
    }

    @Test("Never exceeds 1")
    func clamped() {
        let p = ModelDownloadManager.overallProgress(
            fileFraction: 1, bytesBefore: 9_000, fileBytes: 2_000,
            totalBytes: 10_000, fileIndex: 1, fileCount: 2
        )
        #expect(p == 1)
    }
}

@Suite("Checksum")
struct ChecksumTests {
    @Test("SHA-256 of a known string")
    func known() {
        // echo -n hello | shasum -a 256
        #expect(Checksum.sha256(of: Data("hello".utf8))
            == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

    @Test("Verifies a file's digest case-insensitively")
    func fileVerify() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).txt")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try Checksum.verify(fileAt: url, matches: "2CF24DBA5FB0A30E26E83B2AC5B9E29E1B161E5C1FA7425E73043362938B9824"))
        #expect(try Checksum.verify(fileAt: url, matches: "deadbeef") == false)
    }
}

/// Writes canned bytes for chosen hosts and fails for others, to exercise fallback offline.
private struct FakeDownloader: FileDownloading {
    let behavior: @Sendable (URL) -> Result<Data, any Error>

    func download(from url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        switch behavior(url) {
        case let .success(data):
            progress(0.5)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destination)
            progress(1)
        case let .failure(error):
            throw error
        }
    }
}

private struct FakeError: Error {}

@MainActor
@Suite("Download manager orchestration")
struct DownloadManagerTests {
    private func tempStore() -> ModelStore {
        ModelStore(modelsRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    private func model(files: [ModelFile], cdn: URL? = nil) -> ModelDescriptor {
        ModelDescriptor(
            id: "m", displayName: "M", tier: .lite, capabilities: [.text],
            minRAMGB: 8, recommendedRAMGB: 8, quantization: "q4",
            source: ModelSource(huggingFaceRepo: "org/repo", cdnBaseURL: cdn),
            files: files
        )
    }

    @Test("Successful download installs every file")
    func success() async {
        let store = tempStore()
        let downloader = FakeDownloader { _ in .success(Data("weights".utf8)) }
        let manager = ModelDownloadManager(store: store, downloader: downloader)
        let m = model(files: [ModelFile(name: "a.bin", sizeBytes: 7, sha256: "")])

        await manager.performDownload(m)

        #expect(manager.state(for: m) == .installed)
        #expect(FileManager.default.fileExists(atPath: store.directory(for: m).appendingPathComponent("a.bin").path))
        try? FileManager.default.removeItem(at: store.modelsRoot)
    }

    @Test("Falls back to the CDN when Hugging Face fails")
    func fallback() async {
        let store = tempStore()
        let downloader = FakeDownloader { url in
            url.host == "huggingface.co" ? .failure(FakeError()) : .success(Data("weights".utf8))
        }
        let manager = ModelDownloadManager(store: store, downloader: downloader)
        let m = model(files: [ModelFile(name: "a.bin", sizeBytes: 7, sha256: "")],
                      cdn: URL(string: "https://cdn.example.com/repo/"))

        await manager.performDownload(m)

        #expect(manager.state(for: m) == .installed)
        try? FileManager.default.removeItem(at: store.modelsRoot)
    }

    @Test("Fails when every source fails")
    func allFail() async {
        let store = tempStore()
        let downloader = FakeDownloader { _ in .failure(FakeError()) }
        let manager = ModelDownloadManager(store: store, downloader: downloader)
        let m = model(files: [ModelFile(name: "a.bin", sizeBytes: 7, sha256: "")])

        await manager.performDownload(m)

        if case .failed = manager.state(for: m) {} else {
            Issue.record("expected failed state, got \(manager.state(for: m))")
        }
        try? FileManager.default.removeItem(at: store.modelsRoot)
    }

    @Test("Checksum mismatch fails the install")
    func checksumMismatch() async {
        let store = tempStore()
        let downloader = FakeDownloader { _ in .success(Data("weights".utf8)) }
        let manager = ModelDownloadManager(store: store, downloader: downloader)
        let m = model(files: [ModelFile(name: "a.bin", sizeBytes: 7, sha256: String(repeating: "0", count: 64))])

        await manager.performDownload(m)

        #expect(manager.state(for: m) == .failed("checksumMismatch(file: \"a.bin\")"))
        try? FileManager.default.removeItem(at: store.modelsRoot)
    }

    @Test("A model with no files cannot be downloaded (placeholder)")
    func emptyFilesGuarded() async {
        let store = tempStore()
        let downloader = FakeDownloader { _ in .success(Data("x".utf8)) }
        let manager = ModelDownloadManager(store: store, downloader: downloader)
        let placeholder = model(files: [])

        manager.download(placeholder)

        #expect(manager.state(for: placeholder) == .failed("No download available for this model yet"))
    }

    @Test("Delete removes installed files and resets state")
    func delete() async throws {
        let store = tempStore()
        let downloader = FakeDownloader { _ in .success(Data("weights".utf8)) }
        let manager = ModelDownloadManager(store: store, downloader: downloader)
        let m = model(files: [ModelFile(name: "a.bin", sizeBytes: 7, sha256: "")])

        await manager.performDownload(m)
        #expect(manager.state(for: m) == .installed)

        try manager.delete(m)
        #expect(manager.state(for: m) == .notInstalled)
        #expect(!FileManager.default.fileExists(atPath: store.directory(for: m).path))
    }
}
