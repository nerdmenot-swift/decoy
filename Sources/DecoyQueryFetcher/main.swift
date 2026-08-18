import DecoyAdapterKit
import Foundation

/// Fetches the four snapshots that come from a query rather than from a file.
///
///     swift run decoy-fetch wikidata-names
///     swift run decoy-fetch wikidata-colours
///     swift run decoy-fetch wikidata-terms
///     swift run decoy-fetch statistics-names
///     swift run decoy-fetch korean-surnames --table DT_XXXXXXX   (needs a KOSIS key)
///     swift run decoy-fetch all
///
/// **Run by hand, not by the build.** Every other source Decoy uses is a URL with an
/// integrity hash, which is what makes a silently changed upstream fail the build instead of
/// quietly altering everyone's fixtures. These four answer a query: there is no file to hash
/// and no version to pin. So the query is run deliberately, its result committed beside the
/// query that produced it, and anyone can re-run and diff — which is a stronger guarantee
/// than a hash over somebody else's server, because it can be checked by inspection.
///
/// Two of them resume rather than restart. Fifty languages at three queries each is a long,
/// polite crawl over shared infrastructure, and re-asking for what is already on disk wastes
/// somebody else's rate limit as well as this session's time. Delete the file to force a
/// full refresh.

let arguments = CommandLine.arguments
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Tools")
    .appendingPathComponent("adapters")
let dataDirectory = root.appendingPathComponent("data")

func note(_ line: String) {
    FileHandle.standardError.write(Data((line + "\n").utf8))
}

func fail(_ line: String) -> Never {
    note("error: \(line)")
    exit(1)
}

/// Writes a snapshot, creating the directory the first time.
func write(_ name: String, _ document: OrderedJSON) {
    do {
        try FileManager.default.createDirectory(
            at: dataDirectory, withIntermediateDirectories: true)
        try Data(document.rendered.utf8)
            .write(to: dataDirectory.appendingPathComponent("\(name).json"))
    } catch {
        fail("could not write \(name).json: \(error)")
    }
}

let retrieved = Endpoint.today

// MARK: - Wikidata names

func wikidataNames() async {
    let name = "wikidata-names"
    // Resumed from disk, and the order on disk is kept: the file is a diff people read.
    var order: [String] = []
    var out: [String: OrderedJSON] = [:]

    if let data = try? Data(
        contentsOf: dataDirectory.appendingPathComponent("\(name).json")),
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let held = root["names"] as? [String: [String: [String]]]
    {
        for (code, _) in WikidataQueries.nameLanguages where held[code] != nil {
            order.append(code)
            out[code] = .object(
                WikidataQueries.nameClasses.compactMap { entry in
                    held[code]?[entry.kind].map { (entry.kind, .array($0.map(OrderedJSON.string))) }
                })
        }
        if !order.isEmpty { note("resuming; \(order.count) locales already fetched") }
    }

    for (code, languageID) in WikidataQueries.nameLanguages where out[code] == nil {
        var kinds: [(key: String, value: OrderedJSON)] = []

        for (kind, classID) in WikidataQueries.nameClasses {
            let query = WikidataQueries.nameQuery(
                class: classID, language: languageID, code: code)
            guard let bindings = await Endpoint.sparql(query, attempts: 4, backoff: 4, log: note)
            else {
                // A failed query used to be skipped, which wrote the locale with that
                // category simply absent — indistinguishable from "Wikidata has no Danish
                // female given names". That is exactly what happened: `da` shipped with
                // none, Danish full names fell back to English entirely, and the only trace
                // was a line on stderr in a run nobody kept.
                fail(
                    "\(code) \(kind): endpoint gave up after retries. Re-run to resume — do "
                        + "not commit a snapshot with a category missing, it reads as an "
                        + "absence of data.")
            }

            let labels = bindings.compactMap { Endpoint.value($0, "l") }
            let kept = Endpoint.distinctSorted(labels.filter(Endpoint.usable))
            if kept.count >= WikidataQueries.minimumNames {
                kinds.append((kind, .array(kept.map(OrderedJSON.string))))
            }
            note("\(code) \(kind): \(kept.count) of \(labels.count)")
            await Endpoint.pause(1.2)
        }

        if !kinds.isEmpty {
            order.append(code)
            out[code] = .object(kinds)
        }

        // Written after every locale rather than once at the end. Fifty languages at three
        // queries each is a long stretch of somebody else's rate limit, and losing all of it
        // to a failure on the last one is the kind of thing that only happens once.
        write(
            name,
            .object([
                ("retrieved", .string(retrieved)),
                ("names", .object(order.map { ($0, out[$0]!) })),
            ]))
    }
    note("\nwrote \(order.count) locales")
}

// MARK: - Wikidata colours

func wikidataColours() async {
    let name = "wikidata-colours"

    var order: [String] = []
    var out: [String: OrderedJSON] = [:]
    if let data = try? Data(
        contentsOf: dataDirectory.appendingPathComponent("\(name).json")),
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let colours = root["colours"] as? [String: [String]]
    {
        for (code, _) in WikidataQueries.colourLanguages where colours[code] != nil {
            order.append(code)
            out[code] = .array(colours[code]!.map(OrderedJSON.string))
        }
        if !order.isEmpty { note("resuming; \(order.count) locales already fetched") }
    }

    // One request per distinct language, not per locale: `pt_BR` and `pt_PT` ask Wikidata
    // the same question, and asking it twice spends somebody else's rate limit on a known
    // answer.
    var tags: [String] = []
    var codesFor: [String: [String]] = [:]
    for (code, _) in WikidataQueries.colourLanguages {
        let tag = WikidataQueries.subtag(of: code)
        if codesFor[tag] == nil { tags.append(tag) }
        codesFor[tag, default: []].append(code)
    }

    for tag in tags {
        let codes = codesFor[tag] ?? []
        if codes.allSatisfy({ out[$0] != nil }) { continue }

        guard let bindings = await Endpoint.sparql(WikidataQueries.colourQuery(language: tag), log: note)
        else {
            note("\(tag): endpoint gave up")
            continue
        }

        let rows = bindings.compactMap { binding -> (label: String, english: String?)? in
            guard let label = Endpoint.value(binding, "l") else { return nil }
            return (label, Endpoint.value(binding, "en"))
        }
        let translated =
            tag == "en"
            ? rows
            : rows.filter { $0.english == nil || !WikidataQueries.sameWord($0.english!, $0.label) }
        let untranslated = rows.count - translated.count
        let kept = Endpoint.distinctSorted(translated.map(\.label).filter(Endpoint.usable))

        note(
            "\(tag): \(kept.count) of \(rows.count) (\(untranslated) untranslated) -> "
                + codes.joined(separator: ", "))

        if kept.count >= WikidataQueries.minimumColours {
            for code in codes {
                if out[code] == nil { order.append(code) }
                out[code] = .array(kept.map(OrderedJSON.string))
            }
        }

        write(
            name,
            .object([
                ("retrieved", .string(retrieved)),
                ("colours", .object(order.map { ($0, out[$0]!) })),
            ]))
        await Endpoint.pause(1.5)
    }
    note("\nwrote \(order.count) locales")
}

// MARK: - Wikidata terms

func wikidataTerms() async {
    var sets: [(key: String, value: OrderedJSON)] = []

    for (setName, members) in WikidataQueries.termSets {
        guard
            let bindings = await Endpoint.sparql(
                WikidataQueries.termQuery(members: members), log: note)
        else {
            note("\(setName): endpoint gave up")
            continue
        }
        let languages = WikidataQueries.completeSetsOnly(bindings, order: members)
        sets.append((setName, .object(languages)))
        note("\(setName): \(members.count) members, complete in \(languages.count) languages")
        await Endpoint.pause(1.5)
    }

    write(
        "wikidata-terms",
        .object([("retrieved", .string(retrieved)), ("terms", .object(sets))]))
    note("\nwrote \(sets.count) sets")
}

// MARK: - Statistics offices

func statisticsNames() async {
    var countries: [(key: String, value: OrderedJSON)] = []

    for country in ["NO", "SI"] {
        let rows: [StatisticsQueries.Row]?
        do {
            rows =
                country == "NO"
                ? try await StatisticsQueries.norway(log: note)
                : try await StatisticsQueries.slovenia(log: note)
        } catch {
            fail("\(country): \(error)")
        }

        guard let rows else {
            note("\(country): endpoint gave up")
            continue
        }
        guard rows.count >= 500 else {
            fail("\(StatisticsQueries.Failure.tooFewRows(country: country, found: rows.count))")
        }

        countries.append(
            (
                country,
                .array(
                    rows.map {
                        .object([
                            ("name", .string($0.name)),
                            ("sex", .string($0.sex)),
                            ("count", .double($0.count)),
                        ])
                    })
            ))
        let female = rows.filter { $0.sex == "female" }.count
        note("\(country): \(rows.count) names (\(female) female)")
    }

    write(
        "statistics-names",
        .object([("retrieved", .string(retrieved)), ("countries", .object(countries))]))
    note("\nwrote \(countries.count) countries")
}

// MARK: - Korean surnames

func koreanSurnames() async {
    let arguments = CommandLine.arguments
    func option(_ name: String) -> String? {
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count
        else { return nil }
        return arguments[index + 1]
    }

    guard let key = option("--api-key") ?? ProcessInfo.processInfo.environment["KOSIS_API_KEY"]
    else { fail("\(KosisQuery.Failure.noKey)") }

    // Not defaulted, because guessing it is how you silently fetch the wrong table. Both
    // identifiers are in the URL of the table's own page on kosis.kr:
    //   .../statHtml.do?orgId=101&tblId=DT_1IN1503
    guard let table = option("--table") else {
        fail("""
            --table is required: the KOSIS table identifier, as it appears in the table's
            own page URL (…statHtml.do?orgId=101&tblId=DT_XXXXXXX). Pass --org too if it is
            not Statistics Korea (\(KosisQuery.statisticsKorea)).
            """)
    }
    let org = option("--org") ?? KosisQuery.statisticsKorea
    let period = option("--year") ?? "2015"
    // Which column holds the surname is a property of the table, not of the API.
    let column = option("--column") ?? "C1_NM"

    guard let url = KosisQuery.url(key: key, org: org, table: table, period: period) else {
        fail("could not build the request URL")
    }
    note("fetching \(org)/\(table) for \(period)")

    let decoded: Any
    do { decoded = try await Endpoint.json(from: url) } catch { fail("KOSIS: \(error)") }

    let surnames: [(name: String, count: Double)]
    do {
        surnames = try KosisQuery.aggregate(
            try KosisQuery.rows(from: decoded, classification: column))
    } catch { fail("\(error)") }

    note("\(surnames.count) surnames, commonest \(surnames.first?.name ?? "—")")
    write(
        "korean-surnames",
        .object([
            ("retrieved", .string(retrieved)),
            ("source", .string("KOSIS \(org)/\(table), period \(period)")),
            ("surnames", .array(surnames.map {
                .object([("name", .string($0.name)), ("count", .double($0.count))])
            })),
        ]))
    note("\nwrote korean-surnames.json — review it, then commit")
}

// MARK: - Dispatch

/// Everything `all` runs: the snapshots that need nothing but a network.
let unattended = [
    "wikidata-names", "wikidata-colours", "wikidata-terms", "statistics-names",
]
/// Plus the ones that need something from the person running them, and so are named
/// explicitly or not at all. `korean-surnames` wants a KOSIS key and a table identifier;
/// folding it into `all` would fail the whole run for the other four.
let known = unattended + ["korean-surnames"]
guard arguments.count > 1 else {
    fail("name a snapshot to fetch: \(known.joined(separator: ", ")), or all")
}

let requested = arguments[1] == "all" ? unattended : [arguments[1]]
for choice in requested where !known.contains(choice) {
    fail("unknown snapshot '\(choice)' — expected one of \(known.joined(separator: ", "))")
}

for choice in requested {
    note("=== \(choice)")
    switch choice {
    case "wikidata-names": await wikidataNames()
    case "wikidata-colours": await wikidataColours()
    case "wikidata-terms": await wikidataTerms()
    case "korean-surnames": await koreanSurnames()
    default: await statisticsNames()
    }
}
