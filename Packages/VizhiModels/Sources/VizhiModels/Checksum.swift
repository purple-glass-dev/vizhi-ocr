import CryptoKit
import Foundation

/// SHA-256 helpers for verifying downloaded model files against the catalog's checksums.
public enum Checksum {
    public static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Streams a file through SHA-256 so large weights don't load fully into memory.
    public static func sha256(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while case let chunk = try handle.read(upToCount: 1 << 20) ?? Data(), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Case-insensitive comparison of a file's digest against an expected hex string.
    public static func verify(fileAt url: URL, matches expected: String) throws -> Bool {
        try sha256(ofFileAt: url).caseInsensitiveCompare(expected) == .orderedSame
    }
}
