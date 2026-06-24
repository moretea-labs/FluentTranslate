// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FluentTranslate",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "FluentTranslate", targets: ["FluentTranslate"])
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            pkgConfig: "sqlite3",
            providers: [
                .brew(["sqlite3"]),
                .apt(["libsqlite3-dev"])
            ]
        ),
        .executableTarget(
            name: "FluentTranslate",
            dependencies: ["CSQLite"],
            path: "Sources/FluentTranslate",
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Security")
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)
