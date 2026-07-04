// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VizhiUI",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "VizhiUI", targets: ["VizhiUI"]),
    ],
    dependencies: [
        .package(path: "../VizhiCore"),
        .package(path: "../VizhiModels"),
        .package(path: "../VizhiCapture"),
    ],
    targets: [
        .target(
            name: "VizhiUI",
            dependencies: ["VizhiCore", "VizhiModels", "VizhiCapture"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "VizhiUITests",
            dependencies: ["VizhiUI"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
