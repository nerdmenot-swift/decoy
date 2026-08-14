import Foundation

/// Given names from national civil registries, with real population frequencies.
///
/// Fills:
///   <each>  person.first_name.female   weighted by how many people bear each
///   <each>  person.first_name.male     likewise
///   sv, zh_TW, az  person.last_name.generic
///
/// The one adapter that has to scale by country rather than by locale. Every other source
/// here is one dataset covering the world — CLDR, IANA, GeoNames — because the thing it
/// describes is global. Given names are not: they are recorded by whoever registers births
/// in a jurisdiction, published under that jurisdiction's open-data terms, in that
/// jurisdiction's file format. There is no world registry of names and there is not going
/// to be one.
///
/// So this is a table of countries and a parser per format, and adding a country is a
/// descriptor plus an entry below.
///
/// ## What is deliberately not done
///
/// **Surnames, almost never.** France publishes given names openly and surnames only
/// commercially, and that pattern repeats: birth registers are public record, family-name
/// frequencies usually are not. Sweden is the one exception found — SCB publishes 411,802
/// family names with counts — so the adapter handles them where a register has them and
/// expects not to find them.
///
/// **Never a list of identifiable people.** A register counts how many people hold a name;
/// a roster names them. Election candidate registers, company director filings and academic
/// author lists are open, machine-readable, often CC BY, and every one of them is a list of
/// real people. What is wanted is the count without the roster.
///
/// **Never a transliteration where the locale expects its own script.** `ur` writes `اقدس`,
/// not `Aqdas`.
///
/// **Year is discarded.** The files carry a name's count per birth year, which would give
/// `firstName(bornIn: 1950)` — a different feature. The counts are summed across every year.
///
/// **What the weights describe differs by country, and cannot be made uniform.** Spain,
/// Poland, Finland and Sweden count the living population; the UK counts babies named over
/// thirty years, because that is what the ONS publishes.
public struct CivilNamesAdapter: Adapter {
    public static let id = "civil-names"
    public static let sources = [
        "insee-prenoms", "gender-by-name", "pesel-imiona", "ine-nombres", "dvv-etunimet",
        "scb-namn", "ons-baby-names", "ssb-fornavn", "surs-imena", "az-adlar",
        "moi-surnames", "cbs-shemot",
    ]

    public init() {}

    /// Names borne by fewer than this many people since 1900 are dropped.
    ///
    /// INSEE publishes down to three bearers; keeping that tail would be 39,331 names, most
    /// of them a spelling somebody's registrar accepted once, and a weighted draw would
    /// reach them about never. At 200 it keeps 9,243 names and the weights among them are
    /// exactly INSEE's.
    private static let minimumBearers = 200.0

    /// One row of a register: a name, who bears it, and how many do.
    struct Row: Sendable {
        let name: String
        let sex: String
        let count: Double
    }

    /// One entry per country: which locales it serves, and how to read its file.
    ///
    /// Keeping the format knowledge next to the country rather than in a shared reader is
    /// deliberate — the next registry will delimit differently, spell its columns
    /// differently and mark its residual bucket differently, and a general reader would
    /// grow a flag for each.
    struct Registry: Sendable {
        let country: String
        let locales: [String]
        let source: String
        /// An archive that unpacked to a directory, whose one CSV is found by extension.
        var artifact: String? = nil
        /// Files pinned individually, in the order they are concatenated.
        var files: [String] = []
        /// A committed PxWeb query result rather than a pinned file; see `run`.
        var committed: String? = nil
        /// A register that lists which names exist without counting bearers.
        var weighted = true
        var minimumRows = 1000
        var parse: (@Sendable (URL) throws -> [Row])? = nil
    }

    // MARK: - JavaScript primitives

    /// `String.prototype.trim()`.
    ///
    /// Wider than `.whitespacesAndNewlines` by exactly one character: JavaScript trims
    /// U+FEFF, and every one of these files is published with a byte order mark.
    static func trimmed(_ text: String) -> String {
        func isSpace(_ scalar: Unicode.Scalar) -> Bool {
            scalar == "\u{FEFF}" || Character(scalar).isWhitespace
        }
        let scalars = Array(text.unicodeScalars)
        var start = 0
        var end = scalars.count
        while start < end, isSpace(scalars[start]) { start += 1 }
        while end > start, isSpace(scalars[end - 1]) { end -= 1 }
        return String(String.UnicodeScalarView(scalars[start..<end]))
    }

    /// `Number(text)`, or nil where JavaScript would produce `NaN` or an infinity.
    ///
    /// The trim is not cosmetic. Every one of these files is CRLF, and a value in the last
    /// column arrives as `2618994\r` — Taiwan's population figures and INSEE's counts both
    /// sit there. `Number` trims and Swift's `Double.init` does not, so without this every
    /// last column parses as nothing and the register looks empty.
    static func number(_ text: String) -> Double? {
        let body = trimmed(text)
        if body.isEmpty { return 0 }
        guard let value = Double(body), value.isFinite else { return nil }
        return value
    }

    static func text(of url: URL) throws -> String {
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    /// Lines, with a leading byte order mark dropped.
    ///
    /// `Lines.split` rather than `split(separator: "\n")`: CRLF is a single Swift
    /// `Character`, so splitting on the newline character finds nothing in these files at
    /// all — and every one of them is CRLF.
    static func lines(_ text: String, stripMark: Bool = true) -> [String] {
        var body = text
        if stripMark, body.hasPrefix("\u{FEFF}") { body.removeFirst() }
        return Lines.split(body)
    }

    static func failure(_ detail: String) -> AdapterFailure {
        .shapeChanged(adapter: id, detail: detail)
    }

    // MARK: - Casing

    /// Whether a locale cases its `i` the Turkic way.
    ///
    /// Turkish and Azerbaijani both distinguish dotted from dotless, and CLDR gives them
    /// the same case mappings. Only `az` is served here, and it is not optional: the
    /// Ministry's register holds 3,653 names, and getting this wrong turns every `İbrahim`
    /// into `İbrahim` — a capital I with a combining dot hanging off it — without failing
    /// anything.
    static func isTurkic(_ code: String) -> Bool {
        let language = code.split(separator: "_").first.map(String.init) ?? code
        return language == "tr" || language == "az"
    }

    /// `toLocaleLowerCase(tag)`.
    ///
    /// The default path lowercases the whole string, which is what gives Swift the same
    /// context-sensitive mappings JavaScript has. The Turkic path has to walk scalars
    /// because the rule is about what follows an `I`, and it loses final-sigma handling in
    /// exchange — which costs nothing, because no Turkic locale writes Greek.
    static func lowercased(_ text: String, turkic: Bool) -> String {
        guard turkic else { return text.lowercased() }

        var out = String.UnicodeScalarView()
        let scalars = Array(text.unicodeScalars)
        var index = 0
        while index < scalars.count {
            switch scalars[index] {
            case "\u{0130}":
                // İ lowercases to a plain i, where the default mapping keeps the dot as a
                // combining mark.
                out.append("i")
            case "I":
                if index + 1 < scalars.count, scalars[index + 1] == "\u{0307}" {
                    // A dotted capital written in two pieces: the dot is absorbed.
                    out.append("i")
                    index += 1
                } else {
                    out.append("\u{0131}")
                }
            case let scalar:
                out.append(contentsOf: String(scalar).lowercased().unicodeScalars)
            }
            index += 1
        }
        return String(out)
    }

    /// `toLocaleUpperCase(tag)` of one code point.
    static func uppercased(_ scalar: Unicode.Scalar, turkic: Bool) -> String {
        if turkic, scalar == "i" { return "\u{0130}" }
        return String(scalar).uppercased()
    }

    /// Registries publish names in upper case; nobody stores them that way.
    ///
    /// Capitalises after each hyphen, apostrophe and space, so `JEAN-PIERRE` and `MARIE
    /// THÉRÈSE` come back right rather than as `Jean-pierre`.
    ///
    /// Iterates unicode scalars rather than characters, because the JavaScript iterated
    /// code points. On a decomposed `é` the two disagree: scalars capitalise the `e` and
    /// leave the accent, characters capitalise the pair into a composed `É`.
    static func titleCase(_ name: String, locale: String) -> String {
        let turkic = isTurkic(locale)
        var out = ""
        var atBoundary = true
        for scalar in lowercased(name, turkic: turkic).unicodeScalars {
            out += atBoundary ? uppercased(scalar, turkic: turkic) : String(scalar)
            atBoundary = scalar == "-" || scalar == "'" || scalar == " "
        }
        return out
    }

    /// Drops every `(…)` span, leaving an unclosed `(` where it stands.
    ///
    /// Azerbaijan writes feminine surname forms as `Abbasov (a)`, and the marker would
    /// otherwise put punctuation in a fixture.
    static func withoutParentheticals(_ text: String) -> String {
        var out = ""
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            if characters[index] == "(",
                let close = characters[(index + 1)...].firstIndex(of: ")")
            {
                index = close + 1
                continue
            }
            out.append(characters[index])
            index += 1
        }
        return out
    }

    // MARK: - Parsers

    /// `Name,Gender,Count,Probability`, already aggregated across the four countries and
    /// every year.
    ///
    /// The header carries a UTF-8 byte order mark, which turns the first column name into
    /// something that does not compare equal to `Name` — a classic way to read a CSV as
    /// empty and conclude the schema changed.
    static func genderByName(_ url: URL) throws -> [Row] {
        let all = lines(try text(of: url))
        let header = trimmed(all.first ?? "")
        guard header == "Name,Gender,Count,Probability" else {
            throw failure("Gender-by-Name header is '\(header)' — the schema has changed")
        }
        var rows: [Row] = []
        for line in all.dropFirst() {
            let parts = line.components(separatedBy: ",")
            let name = parts[0]
            guard !name.isEmpty, parts.count > 2 else { continue }
            guard let bearers = number(parts[2]), bearers > 0 else { continue }
            let sex = parts[1] == "M" ? "male" : parts[1] == "F" ? "female" : nil
            if let sex { rows.append(Row(name: name, sex: sex, count: bearers)) }
        }
        return rows
    }

    /// The Ministry of Justice's list of names that may be registered, each with an
    /// etymology. `kişi` is male and `qadın` female.
    ///
    /// Given names and surnames share the file and are told apart by the etymology, which
    /// opens `familiya,` for a family name. That is a prose field being used as a flag, so
    /// the count of each is asserted rather than trusted: a change in how the Ministry
    /// writes its descriptions fails the build instead of silently reclassifying 1,385
    /// surnames as given names.
    ///
    /// Two spellings of one name are written `Abbas // Abas`; the first variant is taken.
    static func azAdlar(_ url: URL) throws -> [Row] {
        guard
            let records = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
                as? [[String: Any]]
        else { throw failure("AZ register is not a JSON array") }

        var rows: [Row] = []
        var surnames = 0
        for record in records {
            let raw = record["personName"] as? String ?? ""
            let name = trimmed(
                withoutParentheticals(raw.components(separatedBy: "//")[0]))
            guard !name.isEmpty else { continue }

            let meaning = record["meaningOfName"] as? String ?? ""
            let isSurname = meaning.range(of: "familiya", options: .caseInsensitive) != nil
            if isSurname { surnames += 1 }

            let gender = record["gender"] as? String
            let sex =
                isSurname
                ? "surname"
                : gender == "kişi" ? "male" : gender == "qadın" ? "female" : nil
            if let sex { rows.append(Row(name: name, sex: sex, count: 1)) }
        }

        guard surnames >= 500 else {
            throw failure(
                "AZ register flagged only \(surnames) rows as 'familiya' — the description "
                    + "wording has changed and surnames are being read as given names")
        }
        return rows
    }

    /// `年度,ranking,lastname,age,人口數` — one row per surname per age bracket, so the
    /// brackets are summed to get the population holding each name.
    ///
    /// Surnames only. Taiwan publishes given-name statistics as a 376-page PDF whose fonts
    /// carry no usable ToUnicode mapping, so it extracts as mojibake.
    static func moiSurnames(_ url: URL) throws -> [Row] {
        let all = lines(try text(of: url))
        let header = trimmed(all.first ?? "")
        guard header.contains("lastname"), header.contains("人口數") else {
            throw failure("MOI header is '\(header)' — the schema has changed")
        }

        // Keyed on code units rather than on the string, because the register spells 周 two
        // ways — U+5468 and the compatibility ideograph U+2F83F — and Swift considers those
        // the same key. See `CodeUnitOrder.key`.
        var order: [String] = []
        var totals: [[UInt16]: Double] = [:]
        for line in all.dropFirst() {
            let parts = line.components(separatedBy: ",")
            guard parts.count >= 5 else { continue }
            let name = trimmed(parts[2])
            guard !name.isEmpty, let people = number(parts[4]), people > 0 else { continue }
            let key = CodeUnitOrder.key(name)
            if totals[key] == nil { order.append(name) }
            totals[key, default: 0] += people
        }
        return order.map {
            Row(name: $0, sex: "surname", count: totals[CodeUnitOrder.key($0)] ?? 0)
        }
    }

    /// Eight sheets, one per sex and population group, each `given name | total | <year>…`
    /// for births from 1949 to 2024. Only the total is read.
    ///
    /// All four population groups are merged rather than only the largest. A Hebrew-language
    /// database in Israel holds the names of everyone in Israel, so merging is what makes
    /// the distribution true and taking one group would be a choice about who counts.
    ///
    /// `..` marks a value the CBS withholds, and parses to nothing.
    static func cbsShemot(_ url: URL) throws -> [Row] {
        let sheets = try XLSX.readWorkbook(at: url)
        var rows: [Row] = []
        var seen = 0

        for sheet in sheets.keys.sorted() {
            // Sheet names are Hebrew and carry the sex: בנות is girls, בנים boys.
            let sex =
                sheet.hasPrefix("בנות") ? "female" : sheet.hasPrefix("בנים") ? "male" : nil
            guard let sex, let table = sheets[sheet] else { continue }
            guard let header = table.firstIndex(where: { $0.first == "prati1" }) else {
                continue
            }
            seen += 1
            for row in table[(header + 1)...] {
                let name = trimmed(row.first ?? "")
                guard !name.isEmpty, row.count > 1, let total = number(row[1]), total > 0
                else { continue }
                rows.append(Row(name: name, sex: sex, count: total))
            }
        }

        guard seen == 8 else {
            throw failure("CBS workbook had \(seen) name sheets, expected 8 — the shape has changed")
        }
        return rows
    }

    /// One name column and one count column, under a header found by its first cell.
    ///
    /// Finland, Sweden and Spain all publish this shape and differ only in which sheets
    /// hold it, what the header cell says, and which column the name is in.
    static func columnar(
        _ url: URL, office: String,
        sheets wanted: [(sheet: String, sex: String, header: [String], name: Int, count: Int)]
    ) throws -> [Row] {
        let sheets = try XLSX.readWorkbook(at: url)
        var rows: [Row] = []

        for spec in wanted {
            guard let table = sheets[spec.sheet] else {
                throw failure("\(office) workbook has no '\(spec.sheet)' sheet — the shape has changed")
            }
            // Matched on as many leading cells as the sheet needs. Spain takes two, because
            // `Orden` heads the rank column and would match a row that is not the header.
            guard
                let header = table.firstIndex(where: { row in
                    row.count >= spec.header.count
                        && zip(row, spec.header).allSatisfy { $0 == $1 }
                })
            else {
                let wanted = spec.header.joined(separator: " | ")
                throw failure("\(office) '\(spec.sheet)' has no '\(wanted)' header row")
            }

            for row in table[(header + 1)...] {
                guard row.count > spec.count else { continue }
                let name = trimmed(row[spec.name])
                guard !name.isEmpty, let bearers = number(row[spec.count]), bearers > 0
                else { continue }
                rows.append(Row(name: name, sex: spec.sex, count: bearers))
            }
        }
        return rows
    }

    /// Six sheets: `kaikki` is every given name a person holds, `ens` only those held as
    /// the *first* given name.
    ///
    /// `ens` is the one that matches what `firstName()` means. Finns commonly carry several
    /// given names and go by one of them, so the two sheets disagree sharply: `Juhani` tops
    /// `kaikki` with 270,972 and does not top `ens` at all, because it is overwhelmingly a
    /// second name.
    static func dvvEtunimet(_ url: URL) throws -> [Row] {
        try columnar(
            url, office: "DVV",
            sheets: [
                ("Miehet ens", "male", ["Etunimi"], 0, 1),
                ("Naiset ens", "female", ["Etunimi"], 0, 1),
            ])
    }

    /// The only register here that publishes family names, and the reason this adapter
    /// handles surnames at all: `Efternamn` carries 411,802 of them with counts.
    ///
    /// Given names come from `Tilltalsnamn` rather than `Förnamn` for the same reason
    /// Finland uses `ens`. A *tilltalsnamn* is the given name a person is actually
    /// addressed by, where `Förnamn` counts every given name they hold.
    static func scbNamn(_ url: URL) throws -> [Row] {
        try columnar(
            url, office: "SCB",
            sheets: [
                ("Tilltalsnamn män", "male", ["Tilltalsnamn"], 0, 1),
                ("Tilltalsnamn kvinnor", "female", ["Tilltalsnamn"], 0, 1),
                ("Efternamn", "surname", ["Efternamn"], 0, 1),
            ])
    }

    /// Two sheets, `Hombres` and `Mujeres`, each `Orden | Nombre | Frecuencia | Edad Media`
    /// over the population census. Names borne by fewer than twenty people nationally are
    /// already excluded upstream.
    ///
    /// The header row is found rather than assumed, because it is not in the same place in
    /// both sheets — row seven in `Hombres` and row six in `Mujeres`, the men's sheet
    /// carrying one extra line of preamble.
    static func ineNombres(_ url: URL) throws -> [Row] {
        try columnar(
            url, office: "INE",
            sheets: [
                ("Hombres", "male", ["Orden", "Nombre"], 1, 2),
                ("Mujeres", "female", ["Orden", "Nombre"], 1, 2),
            ])
    }

    /// A `<year> Count` column heading.
    static func isYearCount(_ label: String) -> Bool {
        let parts = label.components(separatedBy: " ")
        return parts.count == 2 && parts[1] == "Count" && parts[0].count == 4
            && parts[0].allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// `Table_1` girls and `Table_2` boys, each `Name` followed by a rank and a count per
    /// year from 2025 back to 1996. Counts are summed across every year.
    ///
    /// A birth cohort rather than a living population, and worth stating because the other
    /// registers here are not: these are the babies named in England and Wales over thirty
    /// years, so the weights describe who is under thirty rather than who is alive.
    ///
    /// Counts of one or two are redacted as `[x]` under the FOI personal-information
    /// exemption, and parse to nothing.
    static func onsBabyNames(_ url: URL) throws -> [Row] {
        let sheets = try XLSX.readWorkbook(at: url)
        var rows: [Row] = []

        for (sheet, sex) in [("Table_1", "female"), ("Table_2", "male")] {
            guard let table = sheets[sheet] else {
                throw failure("ONS workbook has no '\(sheet)' sheet — the shape has changed")
            }
            guard let header = table.firstIndex(where: { $0.first == "Name" }) else {
                throw failure("ONS '\(sheet)' has no 'Name' header row")
            }
            // Found by name rather than by taking every other column, so a future edition
            // inserting one does not silently sum ranks.
            let columns = table[header].enumerated()
                .filter { isYearCount($0.element) }
                .map(\.offset)
            guard !columns.isEmpty else {
                throw failure("ONS '\(sheet)' has no '<year> Count' columns")
            }

            for row in table[(header + 1)...] {
                let name = trimmed(row.first ?? "")
                guard !name.isEmpty else { continue }
                var total = 0.0
                for index in columns where index < row.count {
                    if let count = number(row[index]) { total += count }
                }
                if total > 0 { rows.append(Row(name: name, sex: sex, count: total)) }
            }
        }
        return rows
    }

    /// `IMIĘ_PIERWSZE,PŁEĆ,LICZBA_WYSTĄPIEŃ`, already aggregated: one row per name, with how
    /// many people in the PESEL register bear it.
    ///
    /// The sex is taken from the column rather than from which file the row came in. The two
    /// are consistent today, and reading the column means they cannot silently stop being
    /// consistent — the register publishes the split for convenience, not as the
    /// authoritative statement.
    static func peselImiona(_ url: URL) throws -> [Row] {
        let all = lines(try text(of: url))
        let header = trimmed(all.first ?? "")
        guard header == "IMIĘ_PIERWSZE,PŁEĆ,LICZBA_WYSTĄPIEŃ" else {
            throw failure("PESEL header is '\(header)' — the schema has changed")
        }
        var rows: [Row] = []
        for line in all.dropFirst() {
            let parts = trimmed(line).components(separatedBy: ",")
            let name = parts[0]
            guard !name.isEmpty, parts.count > 2 else { continue }
            guard let bearers = number(parts[2]), bearers > 0 else { continue }
            let sex =
                parts[1] == "MĘŻCZYZNA" ? "male" : parts[1] == "KOBIETA" ? "female" : nil
            if let sex { rows.append(Row(name: name, sex: sex, count: bearers)) }
        }
        return rows
    }

    /// `sexe;preusuel;annais;nombre`, semicolon-delimited, one row per name per year.
    ///
    /// `1` is male and `2` is female. Rows whose name begins with `_` are INSEE's residual
    /// buckets — `_PRENOMS_RARES` is "every rare name", not a name.
    static func inseePrenoms(_ url: URL) throws -> [Row] {
        let all = lines(try text(of: url), stripMark: false)
        let header = trimmed(all.first ?? "")
        guard header == "sexe;preusuel;annais;nombre" else {
            throw failure("INSEE header is '\(header)' — the schema has changed")
        }

        // Summed per (sex, name) in the order each pair first appears, matching the Map the
        // JavaScript accumulated into — and keyed on code units for the same reason it is
        // in `moiSurnames`.
        var order: [(sex: String, name: String)] = []
        var totals: [[UInt16]: Double] = [:]
        for line in all.dropFirst() {
            let parts = line.components(separatedBy: ";")
            guard parts.count > 3 else { continue }
            let name = parts[1]
            guard !name.isEmpty, !name.hasPrefix("_") else { continue }
            guard let bearers = number(parts[3]), bearers > 0 else { continue }
            let sex = parts[0] == "1" ? "male" : parts[0] == "2" ? "female" : nil
            guard let sex else { continue }

            let key = CodeUnitOrder.key("\(sex)\u{0}\(name)")
            if totals[key] == nil { order.append((sex, name)) }
            totals[key, default: 0] += bearers
        }

        return order.map { entry in
            Row(
                name: entry.name, sex: entry.sex,
                count: totals[CodeUnitOrder.key("\(entry.sex)\u{0}\(entry.name)")] ?? 0)
        }
    }

    // MARK: - The table

    static let registries: [Registry] = [
        Registry(
            country: "EN", locales: ["en"], source: "gender-by-name",
            // Not `names`: two sources cannot both name an artifact the same thing, since
            // an adapter receives them in one flat map.
            artifact: "english", parse: genderByName),
        Registry(
            country: "AZ", locales: ["az"], source: "az-adlar",
            files: ["azerbaijani-names"],
            // A register of permitted names, not a count of bearers. See `apply`.
            weighted: false, minimumRows: 2000, parse: azAdlar),
        Registry(
            country: "TW", locales: ["zh_TW"], source: "moi-surnames",
            files: ["taiwanese-surnames"],
            // 441 surnames clear the threshold, and that is the whole truth rather than a
            // truncation: Chinese surnames are a closed set of a few hundred covering
            // nearly everybody. 陳 alone is held by 2.6 million people.
            minimumRows: 300, parse: moiSurnames),
        Registry(
            country: "IL", locales: ["he"], source: "cbs-shemot",
            files: ["israeli-names"], parse: cbsShemot),
        // Neither an artifact nor a file: PxWeb answers a POST, so there is nothing to pin.
        // `fetch-statistics-names.mjs` runs by hand and its output is committed.
        Registry(
            country: "NO", locales: ["nb_NO"], source: "ssb-fornavn", committed: "NO"),
        Registry(
            country: "SI", locales: ["sl_SI"], source: "surs-imena", committed: "SI"),
        Registry(
            country: "FI", locales: ["fi"], source: "dvv-etunimet",
            files: ["finnish-names"], parse: dvvEtunimet),
        Registry(
            country: "SE", locales: ["sv"], source: "scb-namn",
            files: ["swedish-names"], parse: scbNamn),
        Registry(
            country: "GB", locales: ["en_GB"], source: "ons-baby-names",
            files: ["uk-names"], parse: onsBabyNames),
        Registry(
            country: "ES", locales: ["es"], source: "ine-nombres",
            files: ["spanish-names"], parse: ineNombres),
        Registry(
            country: "PL", locales: ["pl"], source: "pesel-imiona",
            // Plain CSVs rather than a zip, and one per sex, so `files` instead of
            // `artifact`.
            files: ["polish-male", "polish-female"], parse: peselImiona),
        Registry(
            country: "FR", locales: ["fr"], source: "insee-prenoms",
            artifact: "names", parse: inseePrenoms),
    ]

    // MARK: - Run

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        var contributions: [String: [String: Definition]] = [:]
        // Per-locale, because this adapter reads several registries and none is "the
        // primary". English names come from Gender-by-Name and French from INSEE, and
        // crediting both to whichever happens to be first in `sources` would put a French
        // statistics office's name on a list of American given names.
        var sourceByLocale: [String: String] = [:]
        var stats: [String: String] = [:]

        // Loaded once and only if something needs it, so a checkout without the committed
        // query results still builds every registry that ships a file.
        var committedRows: [String: [Row]]? = nil
        func committed() throws -> [String: [Row]] {
            if let committedRows { return committedRows }
            let url = input.dataDirectory.appendingPathComponent("statistics-names.json")
            guard
                let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
                    as? [String: Any],
                let countries = root["countries"] as? [String: [[String: Any]]]
            else { throw Self.failure("data/statistics-names.json is not the expected shape") }

            let parsed = countries.mapValues { rows in
                rows.compactMap { row -> Row? in
                    guard let name = row["name"] as? String, let sex = row["sex"] as? String,
                        let count = (row["count"] as? NSNumber)?.doubleValue
                    else { return nil }
                    return Row(name: name, sex: sex, count: count)
                }
            }
            committedRows = parsed
            return parsed
        }

        /// Thresholds a registry's rows and writes them to every locale it serves.
        ///
        /// `weighted: false` is for a register that lists which names exist without counting
        /// bearers — Azerbaijan publishes the names the Ministry of Justice permits, which
        /// is a different kind of fact from how many people hold one. Thresholding it would
        /// compare against a count it does not have.
        ///
        /// `minimumRows` is for a register that is legitimately small. The default guard
        /// exists to catch a re-pin that silently yields almost nothing.
        func apply(_ registry: Registry, _ rows: [Row]) throws {
            let kept =
                registry.weighted
                ? rows.filter { $0.count >= Self.minimumBearers } : rows
            guard kept.count >= registry.minimumRows else {
                throw Self.failure(
                    "\(registry.source) yielded only \(kept.count) names — verify before re-pinning"
                )
            }

            for code in registry.locales where input.locales.contains(code) {
                var contribution: [String: Definition] = [:]
                var summary: [String] = []

                // `surname` alongside the two sexes, because one register publishes them.
                for kind in ["female", "male", "surname"] {
                    let path =
                        kind == "surname"
                        ? "person.last_name.generic" : "person.first_name.\(kind)"
                    let matching = kept.filter { $0.sex == kind }
                    if matching.isEmpty { continue }

                    let values: [Definition]
                    if registry.weighted {
                        // Sorted on the raw name, and title-cased afterwards, because that
                        // is the order the JavaScript produced — casing can move a name
                        // past its neighbour.
                        let ordered = matching.enumerated().sorted { left, right in
                            if left.element.count != right.element.count {
                                return left.element.count > right.element.count
                            }
                            let a = left.element.name
                            let b = right.element.name
                            if CodeUnitOrder.before(a, b) { return true }
                            if CodeUnitOrder.before(b, a) { return false }
                            // Two rows with the same count and the same name. Swift's sort
                            // is not stable and JavaScript's is, so the original position
                            // breaks the tie rather than the algorithm.
                            return left.offset < right.offset
                        }
                        values = ordered.map {
                            .object([
                                "value": .string(
                                    Self.titleCase($0.element.name, locale: code)),
                                "weight": .number($0.element.count),
                            ])
                        }
                    } else {
                        // An unweighted register ships a plain list. Giving every entry the
                        // same weight would encode a uniform draw as though it had been
                        // measured, and the corpus would carry a number that means nothing.
                        var seen = Set<[UInt16]>()
                        var distinct: [String] = []
                        for row in matching {
                            let cased = Self.titleCase(row.name, locale: code)
                            if seen.insert(CodeUnitOrder.key(cased)).inserted {
                                distinct.append(cased)
                            }
                        }
                        values = CodeUnitOrder.sorted(distinct).map(Definition.string)
                    }

                    contribution[path] = .list(values)
                    let leaf = path.split(separator: ".").last.map(String.init) ?? path
                    summary.append("\(leaf)=\(values.count)")
                }

                contributions[code] = contribution
                sourceByLocale[code] = registry.source
                stats[code] = summary.joined(separator: " ")
            }
        }

        for registry in Self.registries {
            // A committed query result rather than a fetched file. Norway and Slovenia
            // publish through PxWeb, which answers a POST — there is no file to hash and no
            // version to pin, so the query is run by hand and its output committed beside
            // it. Re-runnable and diffable instead of hashed.
            if let country = registry.committed {
                guard let rows = try committed()[country] else {
                    throw Self.failure(
                        "\(registry.source): no '\(country)' in data/statistics-names.json — "
                            + "run Tools/adapters/fetch-statistics-names.mjs")
                }
                try apply(registry, rows)
                continue
            }

            // Two shapes, because registries publish in two shapes. Most ship a zip holding
            // one CSV whose filename carries the edition year, so the name is read rather
            // than hard-coded and re-pinning to a newer edition does not silently stop
            // finding the data. Poland publishes a plain CSV per sex, so there is nothing
            // to look inside.
            let paths: [URL]
            if let name = registry.artifact {
                let directory = try input.artifact(name, for: Self.id)
                let entries = try FileManager.default.contentsOfDirectory(
                    atPath: directory.path)
                guard let file = entries.sorted().first(where: { $0.hasSuffix(".csv") })
                else { throw Self.failure("\(registry.source): no CSV in the artifact") }
                paths = [directory.appendingPathComponent(file)]
            } else {
                paths = try registry.files.map { try input.artifact($0, for: Self.id) }
            }

            // Parsed per file and concatenated, so a registry that splits its publication
            // across several files needs no special case in the parser it shares.
            guard let parse = registry.parse else {
                throw Self.failure("\(registry.source): no parser")
            }
            var rows: [Row] = []
            for path in paths { rows += try parse(path) }
            try apply(registry, rows)
        }

        return AdapterOutput(
            contributions: contributions,
            stats: stats.keys.sorted().map { ($0, stats[$0] ?? "") },
            sourceByLocale: sourceByLocale)
    }
}
