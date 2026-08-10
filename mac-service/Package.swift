// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ILOBoardHost",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "BoardProtocol", targets: ["BoardProtocol"]),
        .library(name: "BoardHostCore", targets: ["BoardHostCore"]),
        .library(name: "BoardUIPrototype", targets: ["BoardUIPrototype"]),
        .executable(name: "ilo-board-host", targets: ["ilo-board-host"]),
        .executable(name: "ilo-board-preview", targets: ["ilo-board-preview"]),
        .executable(name: "ILOBoardMenu", targets: ["ILOBoardMenu"]),
    ],
    targets: [
        .target(name: "BoardProtocol"),
        .target(name: "BoardUIPrototype"),
        .target(
            name: "BoardHostCore",
            dependencies: ["BoardProtocol"],
            linkerSettings: [
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
            dependencies: ["BoardProtocol", "BoardHostCore"],
            exclude: ["Resources"]
        ),
        .testTarget(name: "BoardProtocolTests", dependencies: ["BoardProtocol"]),
        .testTarget(name: "BoardHostCoreTests", dependencies: ["BoardHostCore", "BoardProtocol"]),
        .testTarget(name: "BoardUIPrototypeTests", dependencies: ["BoardUIPrototype"]),
    ]
)
