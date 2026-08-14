import Foundation

/// Month and weekday names per locale, from CLDR's Gregorian calendar data.
///
/// Fills:
///   <each>   date.month.wide / .abbr        and their `_context` forms
///   <each>   date.weekday.wide / .abbr      and their `_context` forms
public struct CLDRDatesAdapter: Adapter {
    public static let id = "cldr-dates"
    public static let sources = ["cldr-48"]

    public init() {}

    private static let weekdayKeys = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
    /// CLDR keys months by number as strings.
    private static let monthKeys = (1...12).map(String.init)

    /// A name set in calendar order, or nil if any key is missing.
    ///
    /// Order is the whole point. The bootstrap corpus stored these alphabetically, which is
    /// invisible while every draw is random and wrong the moment anything indexes them.
    static func ordered(_ source: Any?, _ keys: [String]) -> [String]? {
        guard let table = source as? [String: Any] else { return nil }
        var values: [String] = []
        for key in keys {
            guard let value = table[key] as? String, !value.isEmpty else { return nil }
            values.append(value)
        }
        return values
    }

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        let root = try input.artifact("dates", for: Self.id)
        var contributions: [String: [String: Definition]] = [:]
        var unmapped: [String] = []

        for locale in input.locales {
            guard let cldrCode = CLDR.code(for: locale, overrides: input.cldrOverrides) else {
                continue
            }
            guard let entry = try CLDR.load("ca-gregorian.json", for: cldrCode, under: root),
                let gregorian = CLDR.at(entry, "dates", "calendars", "gregorian")
                    as? [String: Any]
            else {
                unmapped.append(locale)
                continue
            }

            let months = gregorian["months"] as? [String: Any]
            let days = gregorian["days"] as? [String: Any]

            // `format` rather than `stand-alone`: these appear inside a formatted date,
            // which is the context a fixture's month name is used in. Slavic languages
            // inflect the two differently and the stand-alone form would read as a heading.
            let monthsFormat = months?["format"] as? [String: Any]
            let daysFormat = days?["format"] as? [String: Any]
            guard let monthsWide = Self.ordered(monthsFormat?["wide"], Self.monthKeys),
                let monthsAbbr = Self.ordered(monthsFormat?["abbreviated"], Self.monthKeys),
                let daysWide = Self.ordered(daysFormat?["wide"], Self.weekdayKeys),
                let daysAbbr = Self.ordered(daysFormat?["abbreviated"], Self.weekdayKeys)
            else {
                unmapped.append(locale)
                continue
            }

            // The stand-alone forms. CLDR keeps both because they genuinely differ: a
            // Slavic month name inside a date is genitive — "5 stycznia" — and the same
            // month named on its own is nominative, "styczeń". German has one form for
            // both, which is why the distinction looks redundant until it is not.
            let monthsStandalone = months?["stand-alone"] as? [String: Any]
            let daysStandalone = days?["stand-alone"] as? [String: Any]

            var paths: [String: Definition] = [
                "date.month.wide": .list(monthsWide.map(Definition.string)),
                "date.month.abbr": .list(monthsAbbr.map(Definition.string)),
                "date.weekday.wide": .list(daysWide.map(Definition.string)),
                "date.weekday.abbr": .list(daysAbbr.map(Definition.string)),
            ]
            if let value = Self.ordered(monthsStandalone?["wide"], Self.monthKeys) {
                paths["date.month.wide_context"] = .list(value.map(Definition.string))
            }
            if let value = Self.ordered(monthsStandalone?["abbreviated"], Self.monthKeys) {
                paths["date.month.abbr_context"] = .list(value.map(Definition.string))
            }
            if let value = Self.ordered(daysStandalone?["wide"], Self.weekdayKeys) {
                paths["date.weekday.wide_context"] = .list(value.map(Definition.string))
            }
            if let value = Self.ordered(daysStandalone?["abbreviated"], Self.weekdayKeys) {
                paths["date.weekday.abbr_context"] = .list(value.map(Definition.string))
            }
            contributions[locale] = paths
        }

        return AdapterOutput(
            contributions: contributions,
            stats: [
                ("locales", String(contributions.count)),
                ("unmapped", unmapped.joined(separator: ",")),
            ])
    }
}
