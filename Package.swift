// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AIRadar",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "AIRadar", targets: ["AIRadar"]),
    ],
    targets: [
        .executableTarget(
            name: "AIRadar",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "AIRadarTests",
            dependencies: ["AIRadar"],
            exclude: ["Fixtures/CodexRenderedWarning", "Fixtures/CodexRenderedIQHistory"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
