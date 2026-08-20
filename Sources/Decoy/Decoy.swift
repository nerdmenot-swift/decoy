/// Decoy — a seeded fake-data generator for Swift.
///
/// The core module imports no Foundation. Everything here is stdlib-only so the
/// same code compiles and behaves identically on macOS, Linux, and Windows.
/// Foundation interop (`UUID`, `Date`) lives behind `#if canImport` shims so it
/// is a convenience, never a requirement.

/// The library version, surfaced for diagnostics and corpus-compatibility checks.
public enum Decoy {
    public static let version = "1.0.0"

    /// A seed drawn from the system, for callers who do not need reproducibility.
    ///
    /// Every seeded entry point defaults to this, so `Faker(locale:)` and
    /// `forge.generate(100)` work without thinking about seeds at all.
    ///
    /// Capture it when you want the option of reproducing a run later:
    ///
    /// ```swift
    /// let seed = Decoy.randomSeed()
    /// let rows = users.generate(100, seed: seed)
    /// // print(seed) on failure, and the run comes back exactly
    /// ```
    ///
    /// `SystemRandomNumberGenerator` is stdlib rather than Foundation, so this keeps the
    /// core's promise of importing nothing.
    public static func randomSeed() -> UInt64 {
        UInt64.random(in: UInt64.min...UInt64.max)
    }
}
