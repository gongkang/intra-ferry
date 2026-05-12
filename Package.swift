// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "IntraFerry",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "IntraFerryCore", targets: ["IntraFerryCore"]),
        .executable(name: "IntraFerryApp", targets: ["IntraFerryApp"])
    ],
    targets: [
        .target(
            name: "IntraFerryCore",
            dependencies: []
        ),
        .executableTarget(
            name: "IntraFerryApp",
            dependencies: ["IntraFerryCore"]
        ),
        .testTarget(
            name: "IntraFerryCoreTests",
            dependencies: ["IntraFerryCore"]
        )
    ]
)
