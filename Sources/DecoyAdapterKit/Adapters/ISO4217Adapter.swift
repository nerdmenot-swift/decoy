import Foundation

/// Currencies with their names, symbols and numeric codes.
///
/// Names and symbols are CLDR's, per locale; the numeric codes come from the ISO 4217
/// registry itself, because CLDR does not carry them.
///
/// Fills:
///   <each>   finance.currency
public struct ISO4217Adapter: Adapter {
    public static let id = "iso-4217"
    public static let sources = ["cldr-48", "iso-4217-six"]
    public static let attributeTo: String? = "cldr-48"

    public init() {}

    /// Numeric codes out of the registry XML, checked against the pinned publication date.
    ///
    /// The version check is the point: SIX republishes this document in place, so a
    /// silently newer file would change numeric codes under a pinned hash. Failing here
    /// says "re-pin deliberately" rather than shipping the change.
    static func parseRegistry(_ xml: String, expecting version: String, adapter: String) throws
        -> [String: String]
    {
        let published = Self.attribute("Pblshd", in: xml)
        guard published == version else {
            throw AdapterFailure.shapeChanged(
                adapter: adapter,
                detail:
                    "ISO 4217 registry declares Pblshd=\"\(published ?? "")\" but the source "
                    + "descriptor pins \(version). Upstream republished; verify the change and "
                    + "re-pin.")
        }

        var numericFor: [String: String] = [:]
        for entry in xml.components(separatedBy: "<CcyNtry>").dropFirst() {
            guard let code = Self.element("Ccy", in: entry),
                code.count == 3, code.allSatisfy({ $0.isUppercase && $0.isLetter }),
                let numeric = Self.element("CcyNbr", in: entry),
                (1...3).contains(numeric.count), numeric.allSatisfy(\.isNumber)
            else { continue }
            // Entries without a code are the "no universal currency" placeholders.
            numericFor[code] = String(repeating: "0", count: 3 - numeric.count) + numeric
        }

        guard numericFor.count >= 100 else {
            throw AdapterFailure.shapeChanged(
                adapter: adapter,
                detail:
                    "ISO 4217 registry yielded only \(numericFor.count) codes — the document "
                    + "structure has changed")
        }
        return numericFor
    }

    static func attribute(_ name: String, in xml: String) -> String? {
        guard let start = xml.range(of: "\(name)=\""),
            let end = xml.range(of: "\"", range: start.upperBound..<xml.endIndex)
        else { return nil }
        return String(xml[start.upperBound..<end.lowerBound])
    }

    static func element(_ name: String, in xml: String) -> String? {
        guard let start = xml.range(of: "<\(name)>"),
            let end = xml.range(of: "</\(name)>", range: start.upperBound..<xml.endIndex)
        else { return nil }
        return String(xml[start.upperBound..<end.lowerBound])
    }

    /// Currencies still in circulation: no end date, and not marked non-tender.
    static func currentTender(_ currencyData: [String: Any]) -> Set<String> {
        var current = Set<String>()
        guard let region = currencyData["region"] as? [String: Any] else { return current }
        for periods in region.values {
            guard let list = periods as? [[String: Any]] else { continue }
            for period in list {
                for (code, raw) in period {
                    guard let info = raw as? [String: Any] else { continue }
                    if info["_to"] == nil && (info["_tender"] as? String) != "false" {
                        current.insert(code)
                    }
                }
            }
        }
        return current
    }

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        let core = try input.artifact("core", for: Self.id)
        let numbers = try input.artifact("numbers", for: Self.id)
        let list = try input.artifact("list", for: Self.id)

        // The descriptor's pinned version, read from the descriptor itself so the two
        // cannot drift.
        let descriptorURL = input.dataDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("sources/iso-4217-six.json")
        guard
            let descriptor = try JSONSerialization.jsonObject(
                with: Data(contentsOf: descriptorURL)) as? [String: Any],
            let version = descriptor["version"] as? String
        else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id, detail: "sources/iso-4217-six.json has no version")
        }

        let xml = String(decoding: try Data(contentsOf: list), as: UTF8.self)
        let numericFor = try Self.parseRegistry(xml, expecting: version, adapter: Self.id)

        let currencyFile = core.appendingPathComponent("package/supplemental/currencyData.json")
        guard
            let root = try JSONSerialization.jsonObject(with: Data(contentsOf: currencyFile))
                as? [String: Any],
            let currencyData = CLDR.at(root, "supplemental", "currencyData") as? [String: Any]
        else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id, detail: "CLDR currencyData.json is not the expected shape")
        }
        let tender = Self.currentTender(currencyData)

        var contributions: [String: [String: Definition]] = [:]
        var unmapped: [String] = []

        for locale in input.locales {
            guard let cldrCode = CLDR.code(for: locale, overrides: input.cldrOverrides) else {
                continue
            }
            guard let entry = try CLDR.load("currencies.json", for: cldrCode, under: numbers),
                let currencies = CLDR.at(entry, "numbers", "currencies") as? [String: Any]
            else {
                unmapped.append(locale)
                continue
            }

            var rows: [Definition] = []
            for code in tender.sorted() {
                guard let currency = currencies[code] as? [String: Any],
                    let name = currency["displayName"] as? String
                else { continue }
                rows.append(
                    .object([
                        "code": .string(code),
                        "name": .string(name),
                        // Not every currency has a distinct symbol; CLDR falls back to the
                        // code, which is what an interface would show anyway.
                        "symbol": .string((currency["symbol"] as? String) ?? code),
                        // Empty rather than omitted for the handful the registry has not
                        // assigned, so the composite keeps one shape and callers do not get
                        // a column present on some rows and not others.
                        "numericCode": .string(numericFor[code] ?? ""),
                    ]))
            }

            if !rows.isEmpty { contributions[locale] = ["finance.currency": .list(rows)] }
        }

        return AdapterOutput(
            contributions: contributions,
            stats: [
                ("currencies", String(tender.count)),
                ("withNumericCode", String(tender.filter { numericFor[$0] != nil }.count)),
                ("locales", String(contributions.count)),
                ("unmapped", unmapped.joined(separator: ",")),
            ])
    }
}
