import Foundation

/// American surnames with their real frequencies, from the 2010 Census.
///
/// The weights are the point. A list of 24,889 surnames drawn uniformly produces a fixture
/// set where Smith is as rare as Zwiefelhofer, which is not what a real table of people
/// looks like and not what a collision-rate test wants.
///
/// Fills:
///   en    person.last_name.generic   weighted by bearers
public struct USSurnamesAdapter: Adapter {
    public static let id = "us-surnames"
    public static let sources = ["us-census-surnames"]

    public init() {}

    /// Below this many bearers a surname is vanishingly rare, and the tail is most of the
    /// file: 137,364 of the 162,253 names have fewer.
    private static let minimumBearers = 1000

    /// The Census publishes names in upper case; nobody stores them that way.
    ///
    /// Capitalises after each hyphen and apostrophe too, so `O'BRIEN` and `SMITH-JONES`
    /// come back as `O'Brien` and `Smith-Jones` rather than `O'brien` and `Smith-jones`.
    static func titleCase(_ name: String) -> String {
        var out = ""
        var atBoundary = true
        for character in name.lowercased() {
            out.append(atBoundary ? Character(character.uppercased()) : character)
            atBoundary = character == "-" || character == "'" || character == " "
        }
        return out
    }

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        let directory = try input.artifact("surnames", for: Self.id)
        let file = directory.appendingPathComponent("Names_2010Census.csv")
        let csv = String(decoding: try Data(contentsOf: file), as: UTF8.self)

        let lines = Lines.split(csv)
        let header = (lines.first ?? "").components(separatedBy: ",")
        guard let nameColumn = header.firstIndex(of: "name"),
            let countColumn = header.firstIndex(of: "count")
        else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id,
                detail: "Census file has no name/count columns — the schema has changed")
        }

        var rows: [(value: String, weight: Int)] = []
        var dropped = 0

        for line in lines.dropFirst() {
            let fields = line.components(separatedBy: ",")
            guard fields.count > countColumn else { continue }

            let name = fields[nameColumn]
            // A residual bucket, not a surname anybody is called.
            if name == "ALL OTHER NAMES" { continue }

            guard let count = Int(fields[countColumn]), count > 0 else { continue }
            if count < Self.minimumBearers {
                dropped += 1
                continue
            }
            rows.append((Self.titleCase(name), count))
        }

        guard rows.count >= 10_000 else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id,
                detail: "Census file yielded only \(rows.count) surnames — verify before re-pinning")
        }

        let weighted = rows.map { row in
            Definition.object(["value": .string(row.value), "weight": .number(Double(row.weight))])
        }

        return AdapterOutput(
            // `en` rather than `en_US`: `en` is the chain every locale without its own
            // surnames falls through to. Those locales were already getting American
            // surnames; now they get them in realistic proportions.
            contributions: ["en": ["person.last_name.generic": .list(weighted)]],
            stats: [
                ("surnames", String(rows.count)),
                ("belowThreshold", String(dropped)),
                ("mostCommon", "\(rows[0].value) (\(rows[0].weight))"),
            ])
    }
}
