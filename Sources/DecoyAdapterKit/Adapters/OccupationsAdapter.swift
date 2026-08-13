import Foundation

/// Job titles, from the O*NET occupation database.
///
/// Fills:
///   en    person.job_title
public struct OccupationsAdapter: Adapter {
    public static let id = "occupations"
    public static let sources = ["onet"]

    public init() {}

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        let directory = try input.artifact("database", for: Self.id)
        // The archive unpacks to a single versioned directory whose name changes with each
        // release, so it is found rather than named.
        guard
            let root = try FileManager.default
                .contentsOfDirectory(atPath: directory.path).sorted().first
        else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id, detail: "O*NET archive is empty")
        }
        let file = directory.appendingPathComponent("\(root)/Occupation Data.txt")
        let text = String(decoding: try Data(contentsOf: file), as: UTF8.self)

        let lines = text.components(separatedBy: "\n")
        let header = (lines.first ?? "").components(separatedBy: "\t")
        guard header.count > 1, header[1] == "Title" else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id,
                detail: "O*NET header is \(header.joined(separator: "|")) — the schema has changed")
        }

        var titles = Set<String>()
        for line in lines.dropFirst() {
            let fields = line.components(separatedBy: "\t")
            guard fields.count > 1 else { continue }
            let title = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
            // "All Other" is O*NET's residual bucket for occupations too small to code
            // separately — "Managers, All Other" is a category, not a job title.
            if title.isEmpty || title.hasSuffix(", All Other") { continue }
            titles.insert(title)
        }

        guard titles.count >= 500 else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id,
                detail: "O*NET yielded \(titles.count) occupations — verify before re-pinning")
        }

        return AdapterOutput(
            contributions: ["en": ["person.job_title": .list(titles.sorted().map(Definition.string))]],
            stats: [("occupations", String(titles.count))])
    }
}
