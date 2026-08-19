// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChartScout",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ChartScout", targets: ["ChartScout"])],
    targets: [
        .executableTarget(name: "ChartScout"),
        .testTarget(name: "ChartScoutTests", dependencies: ["ChartScout"])
    ]
)
