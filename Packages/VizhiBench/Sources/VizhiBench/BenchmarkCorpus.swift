import Foundation

/// One benchmark sample: an image plus its ground-truth transcription.
public struct BenchmarkItem: Sendable, Equatable {
    /// Stable id, e.g. `tables/invoice-01` (category + base name, relative to the corpus root).
    public let id: String
    /// The category, taken from the immediate parent folder (e.g. `tables`, `math`, `handwriting`).
    public let category: String
    /// The source image to recognize.
    public let imageURL: URL
    /// Expected output (Markdown), read from the sibling `<name>.expected.md`.
    public let referenceMarkdown: String

    public init(id: String, category: String, imageURL: URL, referenceMarkdown: String) {
        self.id = id
        self.category = category
        self.imageURL = imageURL
        self.referenceMarkdown = referenceMarkdown
    }
}

/// A directory of benchmark samples laid out as:
///
///     <root>/<category>/<name>.<png|jpg|jpeg|tiff>      ← the image
///     <root>/<category>/<name>.expected.md              ← its ground truth
///
/// An image without a matching `.expected.md` is skipped (you can drop in images before
/// transcribing them). Loading is pure file I/O — no recognition — so it's cheap and CI-safe.
public struct BenchmarkCorpus: Sendable {
    public let root: URL
    public let items: [BenchmarkItem]

    public init(root: URL, items: [BenchmarkItem]) {
        self.root = root
        self.items = items
    }

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "tiff", "tif", "heic", "webp"]

    /// Walks the corpus root and pairs each image with its `.expected.md`. Items are sorted by id
    /// for stable, reproducible report ordering.
    public static func load(from root: URL, fileManager: FileManager = .default) throws -> BenchmarkCorpus {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return BenchmarkCorpus(root: root, items: [])
        }

        var items: [BenchmarkItem] = []
        for case let url as URL in enumerator {
            guard imageExtensions.contains(url.pathExtension.lowercased()) else { continue }

            let expected = url.deletingPathExtension().appendingPathExtension("expected.md")
            guard let data = try? Data(contentsOf: expected),
                  let reference = String(data: data, encoding: .utf8) else { continue }

            let category = url.deletingLastPathComponent().lastPathComponent
            let name = url.deletingPathExtension().lastPathComponent
            items.append(BenchmarkItem(
                id: "\(category)/\(name)",
                category: category,
                imageURL: url,
                referenceMarkdown: reference
            ))
        }

        items.sort { $0.id < $1.id }
        return BenchmarkCorpus(root: root, items: items)
    }
}
