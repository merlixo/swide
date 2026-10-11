// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Swide",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Swide", targets: ["Swide"]),
    ],
    targets: [
        // Pure logic: project index, search, eviction, Claude state. No UI.
        .target(
            name: "SwideCore",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "Swide",
            dependencies: ["SwideCore"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(
            name: "SwideCoreTests",
            dependencies: ["SwideCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
