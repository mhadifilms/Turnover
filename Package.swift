// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Turnover",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "TurnoverCore",
            path: "Sources/TurnoverCore"
        ),
        .executableTarget(
            name: "TurnoverApp",
            dependencies: ["TurnoverCore"],
            path: "Sources/TurnoverApp"
        ),
    ]
)
