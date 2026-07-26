/// Decoy — a seeded fake-data generator for Swift.
///
/// The core module imports no Foundation. Everything here is stdlib-only so the
/// same code compiles and behaves identically on macOS, Linux, and Windows.
/// Foundation interop (`UUID`, `Date`) lives behind `#if canImport` shims so it
/// is a convenience, never a requirement.

/// The library version, surfaced for diagnostics and corpus-compatibility checks.
public enum Decoy {
    public static let version = "0.0.1"
}
