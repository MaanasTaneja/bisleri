// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ContextKit",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ContextKit", targets: ["ContextKit"])
    ],
    targets: [
        .executableTarget(
            name: "ContextKit",
            path: "ContextKit",
            exclude: [],
            resources: []
        )
    ]
)
