// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ClaudeRadar",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "ClaudeRadar", targets: ["ClaudeRadar"]),
    ],
    targets: [
        .executableTarget(
            name: "ClaudeRadar",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "ClaudeRadarTests",
            dependencies: ["ClaudeRadar"],
            exclude: ["Fixtures/CodexRenderedWarning"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
