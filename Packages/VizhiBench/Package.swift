// swift-tools-version: 6.0
import PackageDescription

// VizhiBench: an offline quality-benchmark harness. Drives any `OCREngine` over a fixed corpus of
// images with ground-truth transcriptions, scores the output (CER/WER with category-aware
// normalization), and emits a Markdown report. The scoring core is pure and CI-tested; the app
// wires real engines (Vision + MLX models) to it behind a `--benchmark` launch argument, since the
// MLX engine needs the Metal library that only the Xcode build produces.
let package = Package(
    name: "VizhiBench",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "VizhiBench", targets: ["VizhiBench"]),
    ],
    dependencies: [
        .package(path: "../VizhiCore"),
    ],
    targets: [
        .target(
            name: "VizhiBench",
            dependencies: ["VizhiCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "VizhiBenchTests",
            dependencies: ["VizhiBench"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
