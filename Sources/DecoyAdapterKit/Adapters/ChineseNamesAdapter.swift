import Foundation

/// Chinese given names and surnames for `zh_CN`.
///
/// Fills:
///   zh_CN  person.first_name.generic   weighted by how many people bear each
///   zh_CN  person.last_name.generic
///
/// ## Why a name generator's data and not a register
///
/// China publishes no open name frequencies. The two datasets with the right shape are
/// both NonCommercial — one has the 2,614 characters used in given names with frequencies
/// by gender, which is exactly what this wants — and the best-*licensed* Chinese corpus is
/// Apache-2.0 and is 1.14 million full names of real people. Decoy refuses rosters, and
/// refused one for Urdu on the same grounds, so being able to read it changes nothing.
///
/// What is left is `popular.txt`: the 500 commonest full names with the number of people
/// holding each. An aggregate count is not a roster — it is the same shape as the US Census
/// surnames — so it can be used.
///
/// ## Given names are recovered, not listed
///
/// Chinese given names are compositional: one or two characters chosen for their meaning,
/// which is why no list of them exists to be licensed. Stripping a known surname off each
/// of the 500 full names and summing the counts recovers 131 given names carrying real
/// population weights. Thin, and the right 131 — a drawn fixture looks like a Chinese
/// person rather than a walk through a dictionary.
public struct ChineseNamesAdapter: Adapter {
    public static let id = "chinese-names"
    public static let sources = ["chinesename"]

    public init() {}

    /// The locale this serves.
    ///
    /// `zh_CN` only. The data is simplified — 陈 rather than 陳 — so it would be wrong for
    /// `zh_TW`, which has 441 frequency-ranked surnames from Taiwan's own interior ministry
    /// and still has no given names.
    private static let locale = "zh_CN"

    private static let minimumGiven = 100
    private static let minimumSurnames = 500

    /// Splits a full name into surname and given name, longest surname first.
    ///
    /// Longest first because 欧阳 must beat 欧: taking the single character would leave
    /// `阳` on the front of the given name and invent a name nobody holds.
    static func split(_ full: String, surnames: Set<String>) -> (surname: String, given: String)? {
        let characters = Array(full)
        for length in stride(from: min(2, characters.count), through: 1, by: -1) {
            let candidate = String(characters[0..<length])
            guard surnames.contains(candidate) else { continue }
            let given = String(characters[length...])
            return given.isEmpty ? nil : (candidate, given)
        }
        return nil
    }

    /// A tab-separated file's first column, or its first two.
    static func rows(_ text: String) -> [[String]] {
        Lines.split(text).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return trimmed.components(separatedBy: "\t")
        }
    }

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        guard input.locales.contains(Self.locale) else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id, detail: "the roster no longer carries `\(Self.locale)`")
        }

        func text(_ artifact: String) throws -> String {
            String(
                decoding: try Data(contentsOf: try input.artifact(artifact, for: Self.id)),
                as: UTF8.self)
        }

        // Every surname the source knows, for splitting. Single-character *and* compound,
        // because a compound has to be recognised to be stripped correctly even though it
        // is not offered as a surname below.
        let known = Set(Self.rows(try text("zh-surnames")).compactMap(\.first))
        guard !known.isEmpty else {
            throw AdapterFailure.shapeChanged(adapter: Self.id, detail: "surnames.txt is empty")
        }

        // Given names, summed over the full names that end in them.
        var order: [String] = []
        var weights: [String: Double] = [:]
        var unsplittable = 0

        for row in Self.rows(try text("zh-popular")) {
            guard row.count >= 2, let count = Double(row[1]), count > 0 else { continue }
            guard let parts = Self.split(row[0], surnames: known) else {
                unsplittable += 1
                continue
            }
            if weights[parts.given] == nil { order.append(parts.given) }
            weights[parts.given, default: 0] += count
        }

        guard order.count >= Self.minimumGiven else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id,
                detail: "recovered \(order.count) given names — verify before re-pinning")
        }

        // Commonest first, then by code unit, which is how every weighted table here is
        // ordered.
        let given = order.sorted { left, right in
            let a = weights[left] ?? 0
            let b = weights[right] ?? 0
            if a != b { return a > b }
            return CodeUnitOrder.before(left, right)
        }

        // Only the single-character surnames. The compounds are mostly ancient or non-Han
        // — 阿伏干, 阿勒根 — and the file carries no frequencies to separate those from
        // 欧阳 and 司马, which are ordinary. Losing a few real ones is the better error.
        let surnames = CodeUnitOrder.sorted(known.filter { $0.count == 1 })
        guard surnames.count >= Self.minimumSurnames else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id,
                detail: "\(surnames.count) single-character surnames — verify before re-pinning")
        }

        return AdapterOutput(
            contributions: [
                Self.locale: [
                    "person.first_name.generic": .list(
                        given.map {
                            .object(["value": .string($0), "weight": .number(weights[$0] ?? 0)])
                        }),
                    // Unweighted, and that is a real weakness rather than an oversight: 王,
                    // 李 and 张 cover about a fifth of China between them and here they are
                    // as likely as any other. The source is a list of what exists, and an
                    // invented distribution would be worse than an honest flat one.
                    "person.last_name.generic": .list(surnames.map(Definition.string)),
                ]
            ],
            stats: [
                ("given", String(given.count)),
                ("surnames", String(surnames.count)),
                ("unsplittable", String(unsplittable)),
            ])
    }
}
