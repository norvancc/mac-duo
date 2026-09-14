// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacDuo",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MacDuo", targets: ["MacDuo"])],
    targets: [
        .target(name: "DuoCore"),
        .executableTarget(name: "MacDuo", dependencies: ["DuoCore"]),
        .testTarget(name: "DuoCoreTests", dependencies: ["DuoCore"])
    ]
)
