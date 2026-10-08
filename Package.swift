// swift-tools-version:5.9
import Foundation
import PackageDescription

// Bird species identification uses BirdNET, whose models are CC BY-NC-SA 4.0 (non-commercial only). It is compiled
// in unless the build says NON_COMMERCIAL=0, which leaves out the feature and its code, for a commercial release.
let nonCommercial = ProcessInfo.processInfo.environment["NON_COMMERCIAL"] != "0"
let flags: [SwiftSetting] = nonCommercial ? [.define("NON_COMMERCIAL")] : []

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
            swiftSettings: [.unsafeFlags(["-Xcc", "-DACCELERATE_NEW_LAPACK"])] + flags,
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(name: "ClapStudio", dependencies: ["ClapCore"], swiftSettings: flags),
        .executableTarget(name: "ClapBench", dependencies: ["ClapCore"]),
        .testTarget(name: "ClapCoreTests", dependencies: ["ClapCore"], swiftSettings: flags),
    ]
)
