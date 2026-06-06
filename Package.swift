// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BrainDead",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "BrainDead", targets: ["BrainDead"])
    ],
    targets: [
        .executableTarget(
            name: "BrainDead",
            path: "BrainDead",
            exclude: [],
            resources: []
        )
    ]
)
