// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClapStudio",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ClapCore", targets: ["ClapCore"]),
        .executable(name: "ClapStudio", targets: ["ClapStudio"]),
    ],
    targets: [
        .target(
            name: "ClapCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(name: "ClapStudio", dependencies: ["ClapCore"]),
        .testTarget(name: "ClapCoreTests", dependencies: ["ClapCore"]),
    ]
)
