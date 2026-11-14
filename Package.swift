// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TranslateDesk",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TranslateCore", targets: ["TranslateCore"]),
        .executable(name: "TranslateDesk", targets: ["TranslateDesk"])
    ],
    targets: [
        .target(
            name: "TranslateCore",
            path: "Sources/TranslateCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "TranslateDesk",
            dependencies: ["TranslateCore"],
            path: "Sources/TranslateDesk",
            resources: [
                .process("Assets")
            ]
        ),
        .testTarget(
            name: "TranslateCoreTests",
            dependencies: ["TranslateCore"],
            path: "Tests/TranslateCoreTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
