// swift-tools-version: 6.0
import PackageDescription

// Root package: the runnable VizhiOCR menubar app, composed from the local feature packages.
// Run during development with `swift run VizhiOCR`. Final signing/notarization/DMG packaging is
// handled by an Xcode app target layered on top of these same packages.
let package = Package(
    name: "VizhiOCR",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "Packages/VizhiCore"),
        .package(path: "Packages/VizhiModels"),
        .package(path: "Packages/VizhiVision"),
        .package(path: "Packages/VizhiMLX"),
        .package(path: "Packages/VizhiCapture"),
        .package(path: "Packages/VizhiUI"),
        .package(path: "Packages/VizhiBench"),
        // Markdown rendering for the result preview, plus native LaTeX typesetting for math blocks.
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.0"),
        .package(url: "https://github.com/mgriebling/SwiftMath", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "VizhiOCR",
            dependencies: [
                "VizhiCore",
                "VizhiModels",
                "VizhiVision",
                "VizhiMLX",
                "VizhiCapture",
                "VizhiUI",
                "VizhiBench",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "SwiftMath", package: "SwiftMath"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
