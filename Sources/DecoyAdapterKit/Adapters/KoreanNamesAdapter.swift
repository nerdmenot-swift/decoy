import Foundation

/// Korean surnames, once somebody has fetched them.
///
/// Fills:
///   ko   person.last_name.generic
///
/// `ko` carries 3,665 Korean given names and no surnames, so `fullName()` composes
/// entirely in English — the coherence rule working correctly over data that is not there.
/// This is the missing half.
///
/// ## Dormant until the snapshot exists
///
/// KOSIS answers only to a registered API key, so this cannot be a pinned artifact and the
/// build cannot fetch it. The snapshot is produced by hand with
/// `swift run decoy-fetch korean-surnames --table <id>` and committed.
///
/// Until then this contributes nothing and says so, rather than failing the build for
/// everybody or being left out of the registry where it would rot. The moment
/// `data/korean-surnames.json` lands, `ko` has surnames with no other edit.
public struct KoreanNamesAdapter: Adapter {
    public static let id = "korean-names"
    public static let sources = ["kosis-surnames"]

    public init() {}

    private static let locale = "ko"
    private static let file = "korean-surnames.json"
    /// Korea has about 250 surnames. Far below that means the wrong table was fetched.
    private static let minimumSurnames = 100

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        let path = input.dataDirectory.appendingPathComponent(Self.file)
        guard let data = try? Data(contentsOf: path) else {
            return AdapterOutput(
                contributions: [:],
                stats: [("awaiting", "run `decoy-fetch korean-surnames` — see the descriptor")])
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = root["surnames"] as? [[String: Any]]
        else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id, detail: "data/\(Self.file) is not { surnames: [...] }")
        }
        guard input.locales.contains(Self.locale) else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id, detail: "the roster no longer carries `\(Self.locale)`")
        }

        var order: [String] = []
        var weights: [String: Double] = [:]
        for row in rows {
            guard let name = (row["name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                let count = (row["count"] as? NSNumber)?.doubleValue, count > 0
            else { continue }
            if weights[name] == nil { order.append(name) }
            weights[name, default: 0] += count
        }

        guard order.count >= Self.minimumSurnames else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id,
                detail:
                    "\(order.count) surnames in the snapshot — Korea has about 250, so this "
                    + "is probably the wrong table; re-run the fetcher and review it")
        }

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
                                "value": .string($0), "weight": .number(weights[$0] ?? 0),
                            ])
                        })
                ]
            ],
            stats: [("surnames", String(sorted.count)), ("commonest", sorted.first ?? "—")])
    }
}
