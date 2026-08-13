import Foundation

/// Media types and their file extensions, from mime-db.
///
/// Fills:
///   base    system.mime_type
public struct MIMETypesAdapter: Adapter {
    public static let id = "mime-types"
    public static let sources = ["mime-db"]

    public init() {}

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        let directory = try input.artifact("db", for: Self.id)
        let file = directory.appendingPathComponent("package/db.json")
        guard
            let db = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
                as? [String: Any]
        else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id, detail: "db.json is not an object")
        }

        var types: [String: Definition] = [:]
        var skipped = 0

        for (type, raw) in db.sorted(by: { $0.key < $1.key }) {
            // Most of mime-db has no extension mapping — it exists to answer "is this type
            // compressible", not "what file is it". Without extensions a drawn type would
            // send fileExtension() to its "bin" fallback, degrading the output rather than
            // broadening it.
            guard let entry = raw as? [String: Any],
                let extensions = entry["extensions"] as? [String], !extensions.isEmpty
            else {
                skipped += 1
                continue
            }
            types[type] = .object([
                "extensions": .list(extensions.sorted().map(Definition.string))
            ])
        }

        guard !types.isEmpty else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id, detail: "mime-db yielded no types with extensions — the schema has changed")
        }

        return AdapterOutput(
            // Handed over nested rather than as dotted paths: media types contain dots
            // (`application/vnd.ms-excel`), and flattening would split one type across
            // several levels of nesting that nothing could look up again.
            contributions: ["base": ["system.mime_type": .object(types)]],
            stats: [
                ("types", String(types.count)), ("withoutExtensions", String(skipped)),
            ])
    }
}
