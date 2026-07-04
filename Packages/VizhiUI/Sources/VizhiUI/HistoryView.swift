import AppKit
import SwiftUI
import VizhiCore

/// Local capture history: recent results with one-click re-copy, per-item delete, and clear-all.
/// Off by default; when disabled, existing entries still show with a hint until cleared.
public struct HistoryView: View {
    @Bindable private var history: CaptureHistoryStore
    private let isEnabled: Bool

    public init(history: CaptureHistoryStore, isEnabled: Bool) {
        self._history = Bindable(history)
        self.isEnabled = isEnabled
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if history.entries.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(history.entries) { entry in
                        row(entry)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 460, minHeight: 420)
    }

    private var header: some View {
        HStack {
            if !isEnabled {
                Label("History is off — enable it in Settings", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Clear All", role: .destructive) { history.clear() }
                .disabled(history.entries.isEmpty)
        }
        .padding(10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath").font(.system(size: 34)).foregroundStyle(.secondary)
            Text(isEnabled ? "No captures yet" : "History is off")
                .font(.headline)
            Text(isEnabled
                 ? "Captures you make will appear here, on this Mac only."
                 : "Turn on “Keep a local capture history” in Settings.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func row(_ entry: HistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.preview).lineLimit(2)
                Text("\(entry.date, format: .dateTime.month().day().hour().minute()) · \(entry.engine)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button { copy(entry) } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless).help("Copy to clipboard")
            Button(role: .destructive) { history.remove(entry.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).help("Delete")
        }
        .padding(.vertical, 2)
    }

    private func copy(_ entry: HistoryEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
    }
}
