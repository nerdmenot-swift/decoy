import Foundation

/// A locale's own path count, as recorded in the gate baseline.
///
/// Native path counts rather than percentages, deliberately. A percentage is relative to
/// the reference locale, so a percentage baseline fails every locale the moment `en`
/// gains paths — punishing an improvement everywhere else. A count only moves when the
/// locale itself moves.
public struct CoverageBaseline: Codable, Equatable {
    public var locales: [String: Int]

    public init(locales: [String: Int]) {
        self.locales = locales
    }
}

/// What comparing a corpus against its baseline found.
public struct CoverageComparison: Equatable {
    /// Locales carrying fewer paths than recorded. The failure condition.
    public struct Regression: Equatable {
        public let locale: String
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

/// Compares measured path counts against a baseline.
///
/// Pure, so it can be tested without a corpus on disk. The gate exists because a corpus
/// is a build artifact nobody diffs: an adapter that stops emitting, or a source that
/// returns less after a re-pin, leaves every test passing and the data quietly thinner.
///
/// Growth is not a failure. An absolute quality threshold would fail everything on its
/// first run — median native coverage is 26% — and be switched off within a week, so this
/// asks only that nothing goes backwards.
public func compareCoverage(
    measured: [String: Int],
    against baseline: CoverageBaseline
) -> CoverageComparison {
    var regressions: [CoverageComparison.Regression] = []
    var improved: [String] = []
    var unlisted: [String] = []

    for (locale, count) in measured {
        guard let expected = baseline.locales[locale] else {
            unlisted.append(locale)
            continue
        }
        if count < expected {
            regressions.append(.init(locale: locale, expected: expected, actual: count))
        } else if count > expected {
            improved.append(locale)
        }
    }

    let missing = baseline.locales.keys.filter { measured[$0] == nil }

    return CoverageComparison(
        regressions: regressions.sorted { $0.locale < $1.locale },
        missing: missing.sorted(),
        unlisted: unlisted.sorted(),
        improved: improved.sorted()
    )
}
