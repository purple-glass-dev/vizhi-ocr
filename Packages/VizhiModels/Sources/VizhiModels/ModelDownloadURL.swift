import Foundation

public extension ModelSource {
    /// Candidate URLs for a file, in priority order: Hugging Face first, then the CDN mirror.
    /// The download manager tries each until one succeeds (docs/MODELS.md, docs/PRIVACY.md).
    func downloadURLs(forFile filename: String) -> [URL] {
        var urls: [URL] = []
        if let hf = URL(string: "https://huggingface.co/\(huggingFaceRepo)/resolve/main/\(filename)") {
            urls.append(hf)
        }
        if let cdn = cdnBaseURL?.appendingPathComponent(filename) {
            urls.append(cdn)
        }
        return urls
    }
}
