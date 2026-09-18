// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClaudeHub",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ClaudeHub", targets: ["ClaudeHub"])],
    targets: [
        .executableTarget(name: "ClaudeHub", path: "Sources/ClaudeHub"),
        .testTarget(
            name: "ClaudeHubTests",
            dependencies: ["ClaudeHub"],
            path: "Tests/ClaudeHubTests"
        ),
    ]
)
