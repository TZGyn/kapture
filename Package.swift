// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Kapture",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Kapture",
            path: "Sources/Kapture"
        )
    ]
)
