import Foundation

/// Vietnamese given names, which no register publishes.
///
/// Fills:
///   vi   person.first_name.female
///   vi   person.first_name.male
///
/// ## Why this one is not a civil register
///
/// Every other given-name source here is a statistics office counting its own population,
/// and `CivilNamesAdapter` exists to read twelve of them. Vietnam is not among them: births
/// are registered and the frequencies are not published, and Wikidata has fifty-seven
/// Vietnamese surnames tagged with `P407` and no given names at all.
///
/// So `vi` drew Vietnamese surnames and English given names — Nguyễn Michael — which reads
/// as a bug to anyone Vietnamese and was invisible to everyone else. A community
/// compilation under MIT is what exists, and it is taken on the reasoning `cities-json` and
/// `airport-data` are already taken on: the names are facts about a language, the
/// compilation carries a licence that composes, and the alternative was nothing.
///
/// ## Unweighted, and that is the honest shape
///
/// A compilation records which names exist, not how many people hold them. Weighting it
/// would mean inventing a distribution and shipping it as though it had been measured —
/// the same refusal `az-adlar` makes, and the reason the corpus can say which of its name
/// tables carry real frequencies and which do not.
///
/// ## Both lengths, because both are names
///
/// Vietnamese given names run to one or two syllables and the source splits them into
/// separate files. Taking only the two-syllable list would lose `An` and `Bình`; taking
/// only the single would lose `An Khang` and `Phương Chi`, which are the more common shape.
/// The two lists do not overlap at all — 1,236 and 334 for men, 1,315 and 256 for women —
/// so they concatenate cleanly.
public struct VietnameseNamesAdapter: Adapter {
    public static let id = "vietnamese-names"
    public static let sources = ["vietnamese-namedb"]

    public init() {}

    /// Below this the upstream has changed shape rather than merely been updated.
    ///
    /// Set well under the ~1,570 each side currently yields. The guard is here to catch a
    /// file that arrives empty or truncated, not to pin a number that is allowed to move.
    private static let minimumNames = 400

    /// The artifacts making up one sex's list, longest form first.
    private static let lists: [(kind: String, artifacts: [String])] = [
        ("female", ["vi-female", "vi-female-single"]),
        ("male", ["vi-male", "vi-male-single"]),
    ]

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        guard input.locales.contains("vi") else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id, detail: "the roster no longer carries `vi`")
        }

        var contribution: [String: Definition] = [:]
        var stats: [(String, String)] = []

        for (kind, artifacts) in Self.lists {
            var names: [String] = []
            for artifact in artifacts {
                let url = try input.artifact(artifact, for: Self.id)
                let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
                for line in Lines.split(text) {
                    let name = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    // A blank line, and nothing else: the files are one name per line with
                    // no header, no comment syntax and no counts.
                    guard !name.isEmpty else { continue }
                    names.append(name)
                }
            }

            let distinct = CodeUnitOrder.sorted(
                Array(names.reduce(into: (seen: Set<[UInt16]>(), kept: [String]())) {
                    if $0.seen.insert(CodeUnitOrder.key($1)).inserted { $0.kept.append($1) }
                }.kept))

            guard distinct.count >= Self.minimumNames else {
                throw AdapterFailure.shapeChanged(
                    adapter: Self.id,
                    detail:
                        "\(kind) yielded \(distinct.count) names — verify before re-pinning")
            }

            contribution["person.first_name.\(kind)"] = .list(distinct.map(Definition.string))
            stats.append((kind, String(distinct.count)))
        }

        return AdapterOutput(contributions: ["vi": contribution], stats: stats)
    }
}
