// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VizhiMLX",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "VizhiMLX", targets: ["VizhiMLX"]),
    ],
    dependencies: [
        .package(path: "../VizhiCore"),
        .package(path: "../VizhiModels"),
        // MLX model runtime: VLM/LLM implementations + Hugging Face hub loading.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.3"),
        // Hub client + tokenizers that mlx-swift-lm's loader macros bridge to.
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "VizhiMLX",
            dependencies: [
                "VizhiCore",
                "VizhiModels",
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            // MLX interop predates Swift 6 strict concurrency; keep this thin wrapper in Swift 5
            // language mode to avoid fighting non-Sendable model types. The rest of the app stays v6.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "VizhiMLXTests",
            dependencies: ["VizhiMLX"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
