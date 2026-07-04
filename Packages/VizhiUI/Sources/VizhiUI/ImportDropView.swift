import SwiftUI
import UniformTypeIdentifiers

/// Drag-and-drop target for PDFs and images. This path needs no Screen Recording permission, so
/// it's the always-available way to OCR a file (see docs/REQUIREMENTS.md FR-2).
public struct ImportDropView: View {
    private let onDropFiles: ([URL]) -> Void
    @State private var isTargeted = false
    @State private var isPickingFile = false

    /// File types accepted by the importer.
    public static let acceptedTypes: [UTType] = [.pdf, .png, .jpeg, .tiff, .heic, .image]

    public init(onDropFiles: @escaping ([URL]) -> Void) {
        self.onDropFiles = onDropFiles
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
            .foregroundStyle(isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "doc.viewfinder").font(.system(size: 36))
                    Text("Drop a PDF or image").font(.headline)
                    Text("Turns into clean Markdown on your clipboard").font(.caption).foregroundStyle(.secondary)
                    Button("Choose File…") { isPickingFile = true }
                        .buttonStyle(.bordered)
                        .padding(.top, 4)
                }
            }
            .frame(minWidth: 360, minHeight: 220)
            .padding()
            .dropDestination(for: URL.self) { urls, _ in
                onDropFiles(urls)
                return !urls.isEmpty
            } isTargeted: { isTargeted = $0 }
            .fileImporter(
                isPresented: $isPickingFile,
                allowedContentTypes: Self.acceptedTypes,
                allowsMultipleSelection: false
            ) { result in
                if case let .success(urls) = result, !urls.isEmpty {
                    onDropFiles(urls)
                }
            }
    }
}
