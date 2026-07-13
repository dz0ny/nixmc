// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "nixmc",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "nixmc",
            path: "Sources/nixmc",
            resources: [.process("Resources")]
        )
    ]
)
