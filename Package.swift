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
            // Use Accelerate's current BLAS/LAPACK headers; the default ones are deprecated since macOS 13.3.
            swiftSettings: [.unsafeFlags(["-Xcc", "-DACCELERATE_NEW_LAPACK"])],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(name: "ClapStudio", dependencies: ["ClapCore"]),
        .executableTarget(name: "ClapBench", dependencies: ["ClapCore"]),
        .testTarget(name: "ClapCoreTests", dependencies: ["ClapCore"]),
    ]
)
