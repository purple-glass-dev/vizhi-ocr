import Foundation
import ImageIO
import UniformTypeIdentifiers
import VizhiCore

/// Writes a captured screen region to disk as a PNG. Used by the region-capture path when the
/// user has opted into keeping screenshot images; imported files never go through here.
public enum ScreenshotSaver {
    public enum SaveError: Error {
        /// ImageIO couldn't create or finalize the PNG at the destination.
        case encodingFailed
    }

    /// Saves `image` into `folder` as `VizhiOCR-Screenshot-<timestamp>.png`, creating the folder if
    /// needed. Returns the written file URL. On a same-second name collision, a numeric suffix keeps
    /// the file distinct rather than overwriting the previous capture.
    @discardableResult
    public static func save(_ image: OCRImage, to folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = uniqueURL(in: folder)

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw SaveError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image.cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw SaveError.encodingFailed
        }
        return url
    }

    /// A timestamped destination that doesn't already exist. The base name matches `OutputWriter`'s
    /// timestamp style; if two captures land in the same second, `-2`, `-3`, … disambiguates.
    private static func uniqueURL(in folder: URL) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let base = "VizhiOCR-Screenshot-\(formatter.string(from: Date()))"

        let first = folder.appendingPathComponent("\(base).png")
        guard FileManager.default.fileExists(atPath: first.path) else { return first }

        var suffix = 2
        while true {
            let candidate = folder.appendingPathComponent("\(base)-\(suffix).png")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            suffix += 1
        }
    }
}
