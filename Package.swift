// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Decoy",
    // NOTE: `platforms` declares Apple minimums ONLY. Linux and Windows are
    // supported implicitly and cannot be listed here -- PackageDescription has
    // no case for them. Portability is enforced by the CI matrix and by the
    // core target importing no Foundation, not by anything in this array.
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "Decoy", targets: ["Decoy"])
    ],
    targets: [
        .target(
            name: "Decoy",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DecoyTests",
            dependencies: ["Decoy"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
