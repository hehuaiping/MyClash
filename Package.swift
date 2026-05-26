// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MyClash",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "MyClashCore",
            targets: ["MyClashCore"]
        ),
        .executable(
            name: "myclash",
            targets: ["MyClashCLI"]
        ),
        .executable(
            name: "myclash-app",
            targets: ["MyClashApp"]
        )
    ],
    targets: [
        .target(
            name: "MyClashCore",
            resources: [
                .copy("Resources/Geo")
            ]
        ),
        .executableTarget(
            name: "MyClashCLI",
            dependencies: ["MyClashCore"]
        ),
        .executableTarget(
            name: "MyClashApp",
            dependencies: ["MyClashCore"]
        ),
        .testTarget(
            name: "MyClashCoreTests",
            dependencies: ["MyClashCore"]
        )
    ]
)
