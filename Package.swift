// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Missting",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "Missting",
            path: "Sources"
        )
    ]
)
