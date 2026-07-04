// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VizhiCapture",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "VizhiCapture", targets: ["VizhiCapture"]),
    ],
    dependencies: [
        .package(path: "../VizhiCore"),
    ],
    targets: [
        .target(
            name: "VizhiCapture",
            dependencies: ["VizhiCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "VizhiCaptureTests",
            dependencies: ["VizhiCapture"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
