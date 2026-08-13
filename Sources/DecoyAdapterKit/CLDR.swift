import Foundation

/// Shared access to the CLDR packages, which six adapters read.
///
/// CLDR ships one directory per locale under `package/main`, and the directories are not
/// the same set as Decoy's roster: some codes exist only at the language level, some carry
/// a script, and a few differ outright. Every adapter reading CLDR therefore needs the same
/// two things — a code translation and a walk down the parts until a directory exists — so
/// they live here rather than being copied five times with five chances to diverge.
public enum CLDR {

    /// Maps a Decoy locale code to CLDR's, honouring the roster's explicit overrides.
    ///
    /// Returns nil where the roster records that a locale has no CLDR equivalent at all,
    /// which is a decision rather than a gap and is why the override table stores nulls.
    public static func code(for locale: String, overrides: [String: String?]) -> String? {
        if let override = overrides[locale] { return override }
        return locale.replacingOccurrences(of: "_", with: "-")
    }

    /// Reads a CLDR file for a locale, falling back to less specific codes.
    ///
    /// `de-AT` has no `units.json` of its own, so the walk drops to `de`. Returning nil
    /// once the parts run out is the answer to "this locale is not in CLDR", which the
    /// callers report rather than treat as an error.
    public static func load(
        _ file: String, for cldrCode: String, under root: URL
    ) throws -> [String: Any]? {
        let parts = cldrCode.split(separator: "-").map(String.init)
        for count in stride(from: parts.count, through: 1, by: -1) {
            let candidate = parts.prefix(count).joined(separator: "-")
            let path = root.appendingPathComponent("package/main/\(candidate)/\(file)")
            guard let data = try? Data(contentsOf: path) else { continue }
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let main = root["main"] as? [String: Any],
                let entry = main[candidate] as? [String: Any]
            else { continue }
            return entry
        }
        return nil
    }

    /// A nested value out of a decoded CLDR entry.
    public static func at(_ node: [String: Any], _ path: String...) -> Any? {
        var cursor: Any? = node
        for key in path {
            guard let level = cursor as? [String: Any] else { return nil }
            cursor = level[key]
        }
        return cursor
    }
}
