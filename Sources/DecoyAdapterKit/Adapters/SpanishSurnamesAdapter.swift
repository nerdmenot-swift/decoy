import Foundation

/// Spanish surnames, weighted by how many people carry them.
///
/// Fills:
///   es   person.last_name.generic
///
/// ## Why this needed a new file format
///
/// `es` had given names from INE and no surnames at all, so a Spanish full name was
/// composed entirely in English — the coherence rule working correctly over data that was
/// not there. INE publishes the surnames, and only as a legacy `.xls`: an OLE2 container
/// of BIFF8 records that `XLSX` cannot open and no tool a build machine is guaranteed to
/// have will convert. Reading it directly was the cheaper risk; see `CFB` and `XLS`.
///
/// ## Cased, because INE publishes in capitals
///
/// The register shouts: `GARCIA`, `MUÑOZ`. So do INSEE's given names, and
/// `CivilNamesAdapter` title-cases those on the way in — the same function is used here so
/// a Spanish full name is cased consistently on both halves rather than `Maria GARCIA`.
///
/// INE also strips acute accents while keeping the eñe, so this ships `Garcia` rather than
/// `García`. That is what the register says, and putting the accents back means a table of
/// which surnames take one, which is authoring rather than reading. The given names
/// already shipping from INE have exactly the same property, so the two halves agree.
///
/// ## `Ambos apellidos`, not the first
///
/// Spain gives everyone two surnames, the father's then the mother's, and the file counts
/// each position separately as well as together. The combined figure is the one that means
/// "how many people carry this name" — counting only first surnames would halve the weight
/// of every name that is commoner as a mother's.
public struct SpanishSurnamesAdapter: Adapter {
    public static let id = "spanish-surnames"
    public static let sources = ["ine-apellidos"]

    public init() {}

    private static let locale = "es"
    /// The sheet holding surnames borne by a hundred people or more.
    ///
    /// The other sheet is 20 to 99, which is 58,000 rows a weighted draw would reach about
    /// never and which every `es` module would carry.
    private static let sheet = "Apellidos >=100"
    private static let minimumSurnames = 20_000

    /// `Orden | Apellido | Total(1º) | … | … | Total(2º) | Ambos apellidos`.
    private static let nameColumn = 1
    private static let firstColumn = 2
    private static let bothColumn = 6

    /// What INE writes where it will not disclose a figure.
    ///
    /// Thirteen surnames carry it, all rare and all recent arrivals — LYU, ADEEL,
    /// MELNYCHENKO. The combined count would be small enough to identify a family, so it is
    /// masked; the first-surname count beside it is published and is used instead.
    ///
    /// Worth naming because of how it fails otherwise. It is not a blank or a marker but a
    /// *number*, so it parses, and sorting by it made ADEEL the commonest surname in Spain
    /// ahead of GARCIA. Nothing would have complained.
    private static let withheld = 9_999_999.0

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        guard input.locales.contains(Self.locale) else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id, detail: "the roster no longer carries `\(Self.locale)`")
        }

        let sheets = try XLS.readWorkbook(at: try input.artifact("apellidos", for: Self.id))
        guard let rows = sheets[Self.sheet] else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id,
                detail: "no '\(Self.sheet)' sheet — INE has renamed it; found \(sheets.keys.sorted())")
        }

        // Ordered by first appearance so the sort below is the only thing deciding order.
        var order: [String] = []
        var weights: [String: Double] = [:]

        for row in rows {
            guard row.count > Self.bothColumn else { continue }
            let name = row[Self.nameColumn].trimmingCharacters(in: .whitespacesAndNewlines)
            // The file opens with three title lines and two header rows; they carry no
            // number in the count column, which is a surer test than counting them off.
            guard !name.isEmpty, let both = Double(row[Self.bothColumn]), both > 0
            else { continue }

            // Where the combined figure is withheld, the first-surname count is not.
            let count: Double
            if both == Self.withheld {
                guard let first = Double(row[Self.firstColumn]), first > 0, first != Self.withheld
                else { continue }
                count = first
            } else {
                count = both
            }

            if weights[name] == nil { order.append(name) }
            weights[name, default: 0] += count
        }

        guard order.count >= Self.minimumSurnames else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id,
                detail: "read \(order.count) surnames — verify before re-pinning")
        }

        // Commonest first, then by code unit, as every weighted table here is ordered.
        let sorted = order.sorted { left, right in
            let a = weights[left] ?? 0
            let b = weights[right] ?? 0
            if a != b { return a > b }
            return CodeUnitOrder.before(left, right)
        }

        return AdapterOutput(
            contributions: [
                Self.locale: [
                    "person.last_name.generic": .list(
                        sorted.map {
                            .object([
                                "value": .string(
                                    CivilNamesAdapter.titleCase($0, locale: Self.locale)),
                                "weight": .number(weights[$0] ?? 0),
                            ])
                        })
                ]
            ],
            stats: [("surnames", String(sorted.count)), ("commonest", sorted.first ?? "—")])
    }
}
