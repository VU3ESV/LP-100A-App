// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LP-100A-App",
    platforms: [.macOS(.v14)],
    products: [
        // Standalone .app
        .executable(name: "LP-100A-App", targets: ["LP100AAppMain"]),
        // Plugin library consumed by the Amateur Radio Suite container
        .library(name: "LP100AApp", targets: ["LP100AApp"]),
    ],
    dependencies: [
        // RadioPluginKit is consumed as a published library by Git URL, so both
        // this repo's CI (which checks out only this repo) and the suite container
        // resolve the same tag — no sibling checkout required.
        .package(url: "https://github.com/VU3ESV/RadioPluginKit.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "LP100AApp",
            dependencies: [
                .product(name: "RadioPluginKit", package: "RadioPluginKit"),
            ],
            path: "Sources/LP100AApp"
        ),
        .executableTarget(
            name: "LP100AAppMain",
            dependencies: ["LP100AApp"],
            path: "Sources/LP100AAppMain"
        ),
        .testTarget(
            name: "LP100AAppTests",
            dependencies: ["LP100AApp"],
            path: "Tests/LP100AAppTests"
        ),
    ]
)
