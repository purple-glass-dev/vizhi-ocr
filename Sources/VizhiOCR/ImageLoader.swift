import AppKit
import CoreGraphics
import PDFKit
import VizhiCore

enum ImageLoaderError: Error {
    case unsupported(URL)
    case decodeFailed(URL)
}

/// Loads a dropped file into one or more `OCRImage`s: each PDF page becomes an image; image files
/// load directly. This is the import path that works without Screen Recording permission.
enum ImageLoader {
    /// Renders PDF pages at this scale relative to their native size, for legible OCR input.
    static let pdfRenderScale: CGFloat = 2.0

    static func images(from url: URL) throws -> [OCRImage] {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return try pdfImages(url)
        default:
            return [try imageFile(url)]
        }
    }

    private static func imageFile(_ url: URL) throws -> OCRImage {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw ImageLoaderError.decodeFailed(url)
        }
        return OCRImage(cgImage: cgImage)
    }

    private static func pdfImages(_ url: URL) throws -> [OCRImage] {
        guard let document = PDFDocument(url: url) else { throw ImageLoaderError.decodeFailed(url) }
        var images: [OCRImage] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let pixelSize = CGSize(width: bounds.width * pdfRenderScale, height: bounds.height * pdfRenderScale)
            let nsImage = NSImage(size: pixelSize, flipped: false) { rect in
                NSColor.white.setFill()
                rect.fill()
                let context = NSGraphicsContext.current!.cgContext
                context.scaleBy(x: pdfRenderScale, y: pdfRenderScale)
                page.draw(with: .mediaBox, to: context)
                return true
            }
            var proposedRect = CGRect(origin: .zero, size: pixelSize)
            if let cgImage = nsImage.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) {
                images.append(OCRImage(cgImage: cgImage))
            }
        }
        guard !images.isEmpty else { throw ImageLoaderError.decodeFailed(url) }
        return images
    }
}
