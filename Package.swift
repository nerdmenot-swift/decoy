// swift-tools-version: 6.0
import PackageDescription

/// Locales shipped as compiled-in modules, each with the chain it falls back through.
///
/// One target per locale so `import Decoy` does not drag in every locale's data — an
/// app needing German pays for `de`, `en` and `base`, not for all 76. Regenerate the
/// sources with:
///
///     swift run decoy-build-corpus
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

// `Base` is deliberately not a product. It carries the language-neutral data every chain
// ends at — countries, time zones, media types, emoji — and nothing to build a person from,
// so roughly 45 of the 70 corpus-backed generators trap against it. A product named after a
// locale invites exactly that mistake. It stays a *target*, because every other locale
// module imports it.
let localeProducts: [Product] = locales.filter { $0.name != "Base" }.map {
    .library(name: "DecoyLocale\($0.name)", targets: ["DecoyLocale\($0.name)"])
}

let package = Package(
    name: "Decoy",
    // NOTE: `platforms` declares Apple minimums ONLY. Linux and Windows are
    // supported implicitly and cannot be listed here -- PackageDescription has
    // no case for them. Portability comes from the core target importing no
    // Foundation, and is meant to be checked by the three jobs in ci.yml -- which
    // has never executed, because this repository has no remote.
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "Decoy", targets: ["Decoy"]),
        .executable(name: "decoy-build-corpus", targets: ["DecoyCorpusBuilder"]),
        .executable(name: "decoy-fetch", targets: ["DecoyQueryFetcher"]),
        .executable(name: "decoy-assets", targets: ["DecoyAssetBuilder"]),
        .executable(name: "decoy-compile-corpus", targets: ["DecoyCorpusCompiler"]),
        .executable(name: "decoy-inspect", targets: ["DecoyCorpusInspector"]),
        .executable(name: "decoy-validate", targets: ["DecoyCorpusValidator"]),
    ] + localeProducts,
    targets: [
        // The corpus build pipeline, being ported from Tools/adapters/*.mjs. Kept out of
        // the Decoy library entirely: none of it ships to anybody who installs the package.
        .target(
            name: "DecoyAdapterKit",
            dependencies: ["Decoy"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "Decoy",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The build tools' testable core. Split out of the executables because a target
        // with top-level code cannot be imported by tests, which left the attribution
        // rule and the coverage gate -- the two things that must be right -- untestable.
        .target(
            name: "DecoyCorpusKit",
            dependencies: ["Decoy"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The pipeline driver: acquires every pinned artifact, runs the adapters, merges
        // their claims, trains the models and writes the intermediate the compiler reads.
        .executableTarget(
            name: "DecoyCorpusBuilder",
            dependencies: ["Decoy", "DecoyAdapterKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The four snapshots that come from a query rather than a file. Run by hand; see
        // the tool's own header for why they are committed rather than hashed.
        .executableTarget(
            name: "DecoyQueryFetcher",
            dependencies: ["DecoyAdapterKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The brand assets, drawn from computed geometry. Nothing else depends on it and
        // it is run only when the mark changes.
        .executableTarget(
            name: "DecoyAssetBuilder",
            dependencies: ["DecoyAdapterKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // A host build tool, so unlike the library it may use Foundation freely.
        .executableTarget(
            name: "DecoyCorpusCompiler",
            dependencies: ["Decoy", "DecoyCorpusKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Also host-only, and likewise free to use Foundation.
        .executableTarget(
            name: "DecoyCorpusInspector",
            dependencies: ["Decoy", "DecoyCorpusKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Checks a contribution before it lands: paths nothing draws, template tokens
        // that expand to nothing, licence metadata contradicting the text beside it.
        .executableTarget(
            name: "DecoyCorpusValidator",
            dependencies: ["Decoy"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DecoyTests",
            dependencies: [
                "Decoy", "DecoyCorpusKit", "DecoyAdapterKit",
                "DecoyLocaleEN", "DecoyLocaleDE", "DecoyLocaleJA",
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ] + localeTargets
)
