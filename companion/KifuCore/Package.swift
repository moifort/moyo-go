// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "KifuCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "KifuCore", targets: ["KifuCore"]),
    ],
    targets: [
        .target(name: "KifuCore"),
        .testTarget(
            name: "KifuCoreTests",
            dependencies: ["KifuCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
