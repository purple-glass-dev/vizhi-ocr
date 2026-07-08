import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import VizhiCore
@testable import VizhiCapture

@Suite("Screenshot saving")
struct ScreenshotSaverTests {
    /// A tiny opaque image, enough to exercise PNG encoding.
    private func makeImage(width: Int = 2, height: Int = 2) -> OCRImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return OCRImage(cgImage: context.makeImage()!)
    }

    private func tempFolder() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vizhi-shots-\(UUID().uuidString)")
        return url
    }

    @Test("Writes a PNG whose name matches the screenshot pattern")
    func writesNamedPNG() throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let url = try ScreenshotSaver.save(makeImage(), to: folder)

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(url.pathExtension == "png")
        #expect(url.lastPathComponent.hasPrefix("VizhiOCR-Screenshot-"))

        // The bytes are a decodable PNG, not just an empty file.
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetType(source) == (UTType.png.identifier as CFString))
        #expect(CGImageSourceCreateImageAtIndex(source, 0, nil) != nil)
    }

    @Test("Creates the destination folder if it doesn't exist")
    func createsFolder() throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(!FileManager.default.fileExists(atPath: folder.path))

        _ = try ScreenshotSaver.save(makeImage(), to: folder)

        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir))
        #expect(isDir.boolValue)
    }

    @Test("A same-second second save gets a distinct filename")
    func avoidsCollision() throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let first = try ScreenshotSaver.save(makeImage(), to: folder)
        let second = try ScreenshotSaver.save(makeImage(), to: folder)

        #expect(first != second)
        #expect(FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
    }
}
