// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "JRunner",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "JRunner",
            path: "Sources/JRunner"
        )
    ]
)
