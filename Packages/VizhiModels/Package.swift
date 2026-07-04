// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VizhiModels",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "VizhiModels", targets: ["VizhiModels"]),
    ],
    targets: [
        .target(
            name: "VizhiModels",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "VizhiModelsTests",
            dependencies: ["VizhiModels"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
