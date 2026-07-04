// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VizhiVision",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "VizhiVision", targets: ["VizhiVision"]),
    ],
    dependencies: [
        .package(path: "../VizhiCore"),
    ],
    targets: [
        .target(
            name: "VizhiVision",
            dependencies: ["VizhiCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "VizhiVisionTests",
            dependencies: ["VizhiVision"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
