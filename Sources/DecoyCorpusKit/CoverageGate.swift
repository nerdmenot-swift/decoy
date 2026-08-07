import Foundation

/// What a locale carries, as recorded in the gate baseline.
///
/// Two numbers, because one of them was not enough. The gate originally recorded paths
/// alone, and CI described it as catching a locale "carrying less of its own data" — but
/// an adapter emitting three surnames where it used to emit 24,889 keeps every path and
/// sails through. Paths catch a field disappearing; values catch it being hollowed out,
/// which is what a silently truncated fetch or a changed upstream schema actually looks
/// like.
public struct LocaleCoverage: Codable, Equatable {
    /// Paths the locale defines itself.
    public var paths: Int
    /// Drawable values across those paths: strings in every table, rows in every
    /// composite. A path defined as explicitly empty contributes none, which is correct
    /// — it is a declaration, not data.
    public var values: Int

    public init(paths: Int, values: Int) {
        self.paths = paths
        self.values = values
    }
}

/// A locale's own path and value counts, as recorded in the gate baseline.
///
/// Native counts rather than percentages, deliberately. A percentage is relative to the
/// reference locale, so a percentage baseline fails every locale the moment `en` gains
/// paths — punishing an improvement everywhere else. A count only moves when the locale
/// itself moves.
public struct CoverageBaseline: Codable, Equatable {
    public var locales: [String: LocaleCoverage]

    public init(locales: [String: LocaleCoverage]) {
        self.locales = locales
    }
}

/// What comparing a corpus against its baseline found.
public struct CoverageComparison: Equatable {
    /// Locales carrying less than the baseline records. The failure condition.
    public struct Regression: Equatable {
        /// Which count went backwards. Named in the failure, because "fewer paths" and
        /// "same paths, a tenth of the values" call for different investigations.
        public enum Dimension: String, Equatable {
            case paths
            case values
        }

        public let locale: String
        public let dimension: Dimension
        public let expected: Int
        public let actual: Int
    }

    public var regressions: [Regression]
    /// In the baseline but absent from the corpus — a locale that vanished entirely.
    public var missing: [String]
    /// In the corpus but not yet in the baseline. Reported, never fatal.
    public var unlisted: [String]
    /// Locales that grew. Reported so the baseline can be refreshed deliberately.
    public var improved: [String]

    public var passes: Bool { regressions.isEmpty && missing.isEmpty }
}

/// Compares measured coverage against a baseline.
///
/// Pure, so it can be tested without a corpus on disk. The gate exists because a corpus
/// is a build artifact nobody diffs: an adapter that stops emitting, or a source that
/// returns less after a re-pin, leaves every test passing and the data quietly thinner.
///
/// Growth is not a failure. An absolute quality threshold would fail everything on its
/// first run — median native coverage is 40% — and be switched off within a week, so this
/// asks only that nothing goes backwards.
public func compareCoverage(
    measured: [String: LocaleCoverage],
    against baseline: CoverageBaseline
) -> CoverageComparison {
    var regressions: [CoverageComparison.Regression] = []
    var improved: [String] = []
    var unlisted: [String] = []

    for (locale, coverage) in measured {
        guard let expected = baseline.locales[locale] else {
            unlisted.append(locale)
            continue
        }
        if coverage.paths < expected.paths {
            regressions.append(
                .init(
                    locale: locale, dimension: .paths,
                    expected: expected.paths, actual: coverage.paths))
        }
        if coverage.values < expected.values {
            regressions.append(
                .init(
                    locale: locale, dimension: .values,
                    expected: expected.values, actual: coverage.values))
        }
        if coverage.paths > expected.paths || coverage.values > expected.values {
            improved.append(locale)
        }
    }

    let missing = baseline.locales.keys.filter { measured[$0] == nil }

    return CoverageComparison(
        regressions: regressions.sorted {
            ($0.locale, $0.dimension.rawValue) < ($1.locale, $1.dimension.rawValue)
        },
        missing: missing.sorted(),
        unlisted: unlisted.sorted(),
        improved: improved.sorted()
    )
}
