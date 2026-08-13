// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ILOBoardHost",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "BoardProtocol", targets: ["BoardProtocol"]),
        .library(name: "BoardHostCore", targets: ["BoardHostCore"]),
        .library(name: "BoardUIPrototype", targets: ["BoardUIPrototype"]),
        .library(name: "ILOBoardMenuSupport", targets: ["ILOBoardMenuSupport"]),
        .executable(name: "ilo-board-host", targets: ["ilo-board-host"]),
        .executable(name: "ilo-board-preview", targets: ["ilo-board-preview"]),
        .executable(name: "ILOBoardMenu", targets: ["ILOBoardMenu"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.2"),
    ],
    targets: [
        .target(name: "BoardProtocol"),
        .target(name: "BoardUIPrototype"),
        .target(
            name: "ILOBoardMenuSupport",
            linkerSettings: [.linkedFramework("ServiceManagement")]
        ),
        .target(
            name: "BoardHostCore",
            dependencies: ["BoardProtocol"],
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ImageIO"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("Network"),
                .linkedFramework("Security"),
            ]
        ),
        .executableTarget(
            name: "ilo-board-host",
            dependencies: ["BoardProtocol", "BoardHostCore"]
        ),
        .executableTarget(
            name: "ilo-board-preview",
            dependencies: ["BoardUIPrototype"]
        ),
        .executableTarget(
            name: "ILOBoardMenu",
            dependencies: [
                "BoardProtocol",
                "BoardHostCore",
                "ILOBoardMenuSupport",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            exclude: ["Resources"]
        ),
        .testTarget(name: "BoardProtocolTests", dependencies: ["BoardProtocol"]),
        .testTarget(name: "BoardHostCoreTests", dependencies: ["BoardHostCore", "BoardProtocol"]),
        .testTarget(name: "BoardUIPrototypeTests", dependencies: ["BoardUIPrototype"]),
        .testTarget(name: "ILOBoardMenuSupportTests", dependencies: ["ILOBoardMenuSupport"]),
        .testTarget(name: "ILOBoardMenuTests", dependencies: ["ILOBoardMenu"]),
    ]
)
