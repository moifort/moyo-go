// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "KifuCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "KifuCore", targets: ["KifuCore"]),
        .executable(name: "kifu-tool", targets: ["kifu-tool"]),
    ],
    targets: [
        .target(name: "KifuCore"),
        .executableTarget(name: "kifu-tool", dependencies: ["KifuCore"]),
        .testTarget(
            name: "KifuCoreTests",
            dependencies: ["KifuCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
