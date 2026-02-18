// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "VFXUpload",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "VFXUploadCore",
            path: "Sources/VFXUploadCore"
        ),
        .executableTarget(
            name: "VFXUploadApp",
            dependencies: ["VFXUploadCore"],
            path: "Sources/VFXUploadApp"
        ),
        .testTarget(
            name: "VFXUploadCoreTests",
            dependencies: ["VFXUploadCore"],
            path: "Tests/VFXUploadCoreTests"
        ),
    ]
)
