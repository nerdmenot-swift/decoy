// swift-tools-version: 6.0
import PackageDescription

/// Locales shipped as compiled-in modules, each with the chain it falls back through.
///
/// One target per locale so `import Decoy` does not drag in every locale's data — an
/// app needing German pays for `de`, `en` and `base`, not for all 76. Regenerate the
/// sources with:
///
///     node Tools/adapters/run.mjs
///     swift run decoy-compile-corpus Tools/adapters/out Corpus/binary \
///       --emit-swift Sources --locales de,ja
let locales: [(name: String, chain: [String])] = [
    ("Base", []),
    ("EN", ["Base"]),
    ("DE", ["EN", "Base"]),
    ("JA", ["EN", "Base"]),
]

let localeTargets: [Target] = locales.map { locale in
    .target(
        name: "DecoyLocale\(locale.name)",
        dependencies: ["Decoy"] + locale.chain.map { .target(name: "DecoyLocale\($0)") },
        swiftSettings: [.swiftLanguageMode(.v6)]
    )
}

let localeProducts: [Product] = locales.map {
    .library(name: "DecoyLocale\($0.name)", targets: ["DecoyLocale\($0.name)"])
}

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
        .library(name: "Decoy", targets: ["Decoy"]),
        .executable(name: "decoy-compile-corpus", targets: ["DecoyCorpusCompiler"]),
        .executable(name: "decoy-inspect", targets: ["DecoyCorpusInspector"]),
    ] + localeProducts,
    targets: [
        .target(
            name: "Decoy",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // A host build tool, so unlike the library it may use Foundation freely.
        .executableTarget(
            name: "DecoyCorpusCompiler",
            dependencies: ["Decoy"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Also host-only, and likewise free to use Foundation.
        .executableTarget(
            name: "DecoyCorpusInspector",
            dependencies: ["Decoy"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DecoyTests",
            dependencies: ["Decoy", "DecoyLocaleEN", "DecoyLocaleDE", "DecoyLocaleJA"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ] + localeTargets
)
