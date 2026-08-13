import Foundation

/// The periodic table, from PubChem.
///
/// Language-neutral, so it lives in `base`. Element names differ between languages, but the
/// symbol and atomic number do not, and a composite row keeps them together.
///
/// Fills:
///   base    science.chemical_element
public struct PeriodicTableAdapter: Adapter {
    public static let id = "periodic-table"
    public static let sources = ["pubchem"]

    public init() {}

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        let path = try input.artifact("table", for: Self.id)
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: path))

        guard let object = root as? [String: Any],
            let table = object["Table"] as? [String: Any],
            let columnsHolder = table["Columns"] as? [String: Any],
            let columns = columnsHolder["Column"] as? [String],
            let rows = table["Row"] as? [[String: Any]]
        else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id, detail: "PubChem response is not the expected shape")
        }

        func index(_ name: String) throws -> Int {
            guard let position = columns.firstIndex(of: name) else {
                throw AdapterFailure.shapeChanged(
                    adapter: Self.id,
                    detail: "PubChem response has no '\(name)' column — the schema has changed")
            }
            return position
        }
        let atomicNumber = try index("AtomicNumber")
        let symbol = try index("Symbol")
        let name = try index("Name")

        /// Cells arrive as strings or numbers depending on the column; both become strings,
        /// because every caller parses them itself and a number that arrived as `14` is not
        /// more trustworthy for having passed through a float.
        func cell(_ row: [String: Any], _ position: Int) -> String {
            guard let cells = row["Cell"] as? [Any], position < cells.count else { return "" }
            let value = cells[position]
            if let text = value as? String { return text }
            if let number = value as? NSNumber { return number.stringValue }
            return ""
        }

        let elements =
            rows
            .map { row in
                (
                    atomicNumber: cell(row, atomicNumber),
                    name: cell(row, name),
                    symbol: cell(row, symbol)
                )
            }
            .sorted { (Int($0.atomicNumber) ?? 0) < (Int($1.atomicNumber) ?? 0) }

        // 118 named elements as of IUPAC's 2016 additions. Fewer means a truncated
        // response; more means something was added and the corpus should be reviewed
        // rather than silently extended.
        guard elements.count == 118 else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id,
                detail: "expected 118 elements, got \(elements.count) — verify before re-pinning")
        }

        let table_ = elements.map { element in
            Definition.object([
                "atomicNumber": .string(element.atomicNumber),
                "name": .string(element.name),
                "symbol": .string(element.symbol),
            ])
        }

        return AdapterOutput(
            contributions: ["base": ["science.chemical_element": .list(table_)]],
            stats: [("elements", String(elements.count))])
    }
}
