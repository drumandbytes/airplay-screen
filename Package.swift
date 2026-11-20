// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AirplayScreen",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "AirplayScreen", path: "Sources/AirplayScreen"),
        .testTarget(name: "AirplayScreenTests", dependencies: ["AirplayScreen"], path: "Tests/AirplayScreenTests"),
    ]
)
