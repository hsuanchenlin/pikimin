// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pikimin",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Pikimin",
            path: "Sources"
        )
    ]
)
