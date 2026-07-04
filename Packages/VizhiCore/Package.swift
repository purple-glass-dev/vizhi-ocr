// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VizhiCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "VizhiCore", targets: ["VizhiCore"]),
    ],
    targets: [
        .target(
            name: "VizhiCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "VizhiCoreTests",
            dependencies: ["VizhiCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
