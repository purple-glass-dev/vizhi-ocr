import Foundation

public enum ModelDownloadError: Error, Equatable {
    case noSourcesConfigured(file: String)
    case allSourcesFailed(file: String)
    case httpError(url: URL, status: Int)
    case invalidResponse(url: URL)
    case checksumMismatch(file: String)
}

/// Downloads a single file with fractional progress. Abstracted so the orchestration can be unit
/// tested with a fake, and so the transport (URLSession today) can be swapped without touching the
/// manager.
public protocol FileDownloading: Sendable {
    func download(
        from url: URL,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws
}

/// `URLSession`-backed downloader using a delegate-driven `URLSessionDownloadTask` for efficient
/// chunked transfer and accurate progress. Honors Swift task cancellation by cancelling the
/// underlying download.
///
/// NOTE: cross-launch resume (reusing a partial file via resumeData) is a follow-up; this focuses
/// on fast, watchable downloads with progress.
public struct URLSessionFileDownloader: FileDownloading {
    public init() {}

    public func download(
        from url: URL,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let delegate = DownloadTaskDelegate(url: url, progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let tempLocation = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, any Error>) in
                delegate.continuation = continuation
                let task = session.downloadTask(with: URLRequest(url: url))
                delegate.task = task
                task.resume()
            }
        } onCancel: {
            delegate.task?.cancel()
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: tempLocation, to: destination)
    }
}

/// Bridges `URLSessionDownloadTask` callbacks to a checked continuation. One instance per download,
/// so its callbacks are serialized on the session's delegate queue.
private final class DownloadTaskDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let url: URL
    private let progress: @Sendable (Double) -> Void
    var continuation: CheckedContinuation<URL, any Error>?
    weak var task: URLSessionDownloadTask?

    init(url: URL, progress: @escaping @Sendable (Double) -> Void) {
        self.url = url
        self.progress = progress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            continuation?.resume(throwing: ModelDownloadError.httpError(url: url, status: http.statusCode))
            continuation = nil
            return
        }
        // `location` is only valid during this call, so move it somewhere stable before returning.
        let stable = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: stable)
            continuation?.resume(returning: stable)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error else { return } // success is handled in didFinishDownloadingTo
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
