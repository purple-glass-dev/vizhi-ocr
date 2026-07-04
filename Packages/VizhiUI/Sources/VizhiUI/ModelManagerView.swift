import SwiftUI
import VizhiModels

/// Lists AI models with their tier, size, and a "Recommended" badge, and drives downloads through
/// the live `ModelDownloadManager` (progress, verify, install, cancel, delete).
public struct ModelManagerView: View {
    private let presentations: [ModelPresentation]
    private let downloads: ModelDownloadManager
    /// The model currently selected for AI capture, if any.
    private let activeModelID: String?
    private let onDownload: (ModelDescriptor) -> Void
    private let onCancel: (ModelDescriptor) -> Void
    private let onDelete: (ModelDescriptor) -> Void
    private let onUse: (ModelDescriptor) -> Void

    public init(
        presentations: [ModelPresentation],
        downloads: ModelDownloadManager,
        activeModelID: String?,
        onDownload: @escaping (ModelDescriptor) -> Void,
        onCancel: @escaping (ModelDescriptor) -> Void,
        onDelete: @escaping (ModelDescriptor) -> Void,
        onUse: @escaping (ModelDescriptor) -> Void
    ) {
        self.presentations = presentations
        self.downloads = downloads
        self.activeModelID = activeModelID
        self.onDownload = onDownload
        self.onCancel = onCancel
        self.onDelete = onDelete
        self.onUse = onUse
    }

    public var body: some View {
        List(presentations, id: \.model.id) { item in
            row(for: item)
                .padding(.vertical, 4)
        }
        .frame(minWidth: 480, minHeight: 320)
    }

    @ViewBuilder
    private func row(for item: ModelPresentation) -> some View {
        let state = downloads.state(for: item.model)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.model.displayName).font(.headline)
                    Text(item.model.tier.displayName)
                        .font(.caption2).padding(.horizontal, 6).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                    if item.isRecommended {
                        Text("Recommended").font(.caption2.bold()).foregroundStyle(.tint)
                    }
                }
                if !item.model.summary.isEmpty {
                    Text(item.model.summary)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(DownloadStatusPresentation.label(for: state, fallback: item.statusText))
                    .font(.caption).foregroundStyle(.secondary)
                if let fraction = DownloadStatusPresentation.fraction(for: state) {
                    ProgressView(value: fraction).frame(maxWidth: 260)
                }
            }
            Spacer()
            Text(item.sizeText).font(.caption).foregroundStyle(.secondary)
            controls(for: item, state: state)
        }
    }

    @ViewBuilder
    private func controls(for item: ModelPresentation, state: ModelDownloadState) -> some View {
        if DownloadStatusPresentation.isInstalled(state) {
            if item.model.id == activeModelID {
                Label("Active", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.tint)
            } else {
                Button("Use") { onUse(item.model) }
            }
            Button("Delete", role: .destructive) { onDelete(item.model) }
        } else if DownloadStatusPresentation.isBusy(state) {
            Button("Cancel") { onCancel(item.model) }
        } else if !item.isDownloadable {
            Text("Coming soon").font(.caption).foregroundStyle(.secondary)
        } else {
            Button(isRetry(state) ? "Retry" : "Download") { onDownload(item.model) }
                .disabled(!item.fits)
        }
    }

    private func isRetry(_ state: ModelDownloadState) -> Bool {
        if case .failed = state { return true }
        return false
    }
}
