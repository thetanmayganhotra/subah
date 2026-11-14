// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Subah",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Subah", path: "Sources/Subah")
    ]
)
