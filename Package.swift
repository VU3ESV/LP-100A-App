// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LP-100A-App",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "LP-100A-App", targets: ["LP100AApp"]),
    ],
    targets: [
        .executableTarget(
            name: "LP100AApp",
            path: "Sources/LP100AApp"
        ),
        .testTarget(
            name: "LP100AAppTests",
            dependencies: ["LP100AApp"],
            path: "Tests/LP100AAppTests"
        ),
    ]
)
