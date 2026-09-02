import DecoyAdapterKit
import Foundation

/// Fetches the four snapshots that come from a query rather than from a file.
///
///     swift run decoy-fetch wikidata-names
///     swift run decoy-fetch wikidata-colours
///     swift run decoy-fetch wikidata-terms
///     swift run decoy-fetch statistics-names
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

// MARK: - Language QID verification

/// Checks every hand-typed language QID against the ISO code the table files it under.
///
/// The tables map a language code to a Wikidata item, and every QID in them was typed by
/// hand. A wrong one does not fail: `Q33298` is Filipino, sat in the romanised-names table
/// labelled Kannada, and the query it produced returned several hundred perfectly valid
/// Filipino names for an Indian locale. Nothing downstream can tell those from Kannada
/// ones — that is the whole difficulty. A wrong QID that returns *nothing* reads as "the
/// language is not catalogued"; one that returns another language reads as success.
///
/// Wikidata records a language item's ISO 639-1 code as `P218`, so this is exact rather
/// than a guess: ask the endpoint what code each item claims and compare it to the code the
/// table filed it under. It runs before the fetch it guards, because the point is to fail
/// before writing a snapshot rather than after.
/// Codes where a table deliberately files a language under a different ISO code.
///
/// `nb` against `no` is the only one. `Q9043` is Norwegian, the macrolanguage; the roster
/// carries `nb`, Bokmål. For names that is the pool you want — Bokmål and Nynorsk do not
/// have different given names — so the broader item is the right one and the mismatch is
/// deliberate.
///
/// The same split bit the GLEIF adapter from the opposite direction, where the register
/// files Norway's *company forms* under `no` and the roster looked for `nb`, so seventeen
/// abbreviations went unused. Worth stating twice: this pair is a recurring trap, not a
/// one-off.
let acceptedLanguageMismatch: [String: Set<String>] = ["nb": ["no"]]

/// Items with no ISO 639-1 code that are nonetheless the right item, checked by hand.
///
/// The value is what Wikidata's own English label says, so the entry records the check
/// rather than merely suppressing the failure. Anything not listed here that lacks a code
/// is treated as the wrong item, which is the safer default: `Q33298` has no code either,
/// and it is Filipino sitting where Kannada should be.
///
/// `Q9129` is "Greek", the language as a whole — Wikidata files the ISO code `el` on
/// "Modern Greek" (`Q36510`) instead. The general item is the one wanted for names, which
/// are shared across the variants rather than split between them.
let languagesWithoutISOCode: [String: String] = ["Q9129": "Greek"]

func verifyLanguageQIDs(_ declared: [(code: String, id: String)], label: String) async {
    var expected: [String: Set<String>] = [:]
    for (code, id) in declared {
        expected[id, default: []].insert(String(code.split(separator: "_")[0]))
    }
    guard !expected.isEmpty else { return }

    let values = expected.keys.sorted().map { "wd:\($0)" }.joined(separator: " ")
    let query = """
        SELECT ?i ?code WHERE {
          VALUES ?i { \(values) }
          ?i wdt:P218 ?code .
        }
        """
    guard let bindings = await Endpoint.sparql(query, attempts: 4, backoff: 15, log: note) else {
        fail("\(label): could not verify language QIDs — refusing to fetch on unchecked ones")
    }

    var actual: [String: Set<String>] = [:]
    for binding in bindings {
        guard let uri = Endpoint.value(binding, "i"), let code = Endpoint.value(binding, "code")
        else { continue }
        actual[Endpoint.qid(uri), default: []].insert(code)
    }

    var wrong: [String] = []
    for (id, codes) in expected.sorted(by: { $0.key < $1.key }) {
        if let verified = languagesWithoutISOCode[id] {
            note("\(label): \(id) has no ISO code; accepted as \(verified)")
            continue
        }
        guard let found = actual[id] else {
            // No P218 at all, which is a failure rather than a skip. Every code in these
            // tables *is* an ISO 639-1 code, so the item it points at should carry one; an
            // item with none is far more likely to be the wrong item than a real language
            // the standard forgot.
            //
            // This was learned the hard way twice over. Skipping here is what let the
            // original bug through a *second* time: Q33298 is Filipino, which has no
            // 639-1 code, so the check that was written to catch it passed it silently.
            wrong.append("\(id) is filed under \(codes.sorted().joined(separator: "/")) but Wikidata records no ISO 639-1 code for it")
            continue
        }
        let agreed = codes.contains { code in
            found.contains(code) || (acceptedLanguageMismatch[code]?.contains(where: found.contains) ?? false)
        }
        if !agreed {
            wrong.append(
                "\(id) is filed under \(codes.sorted().joined(separator: "/")) "
                    + "but Wikidata says \(found.sorted().joined(separator: "/"))")
        }
    }

    if !wrong.isEmpty {
        fail(
            "\(label): \(wrong.count) language QID(s) do not match the code they are filed "
                + "under:\n    " + wrong.joined(separator: "\n    "))
    }
    note("\(label): \(expected.count) language QIDs verified against P218")
}

// MARK: - Wikidata names

func wikidataNames() async {
    let name = "wikidata-names"
    await verifyLanguageQIDs(
        WikidataQueries.nameLanguages
            + WikidataQueries.romanisedNameLocales.flatMap { locale in
                // The romanised table lists QIDs without a code beside them, so the codes
                // the pool is *meant* to span are named here and checked like the rest.
                zip(WikidataQueries.romanisedLanguageCodes, locale.languages).map { ($0, $1) }
            },
        label: "wikidata-names")
    // Resumed from disk, and the order on disk is kept: the file is a diff people read.
    var order: [String] = []
    var out: [String: OrderedJSON] = [:]

    if let data = try? Data(
        contentsOf: dataDirectory.appendingPathComponent("\(name).json")),
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let held = root["names"] as? [String: [String: [String]]]
    {
        let resumable =
            WikidataQueries.nameLanguages.map(\.code)
            + WikidataQueries.romanisedNameLocales.map(\.code)
        for code in resumable where held[code] != nil {
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
            // Six attempts backing off twenty seconds at a time, not four at four.
            //
            // The failure this answers looked like a dead endpoint and was not. Three
            // queries for one language go out 1.2 seconds apart, and the third — surnames,
            // the largest — came back truncated, which surfaces as "the data couldn't be
            // read" rather than as throttling. Four retries inside a minute all landed in
            // the same window and the run aborted saying Wikidata had given up. The same
            // query, alone, returns four thousand rows in half a second.
            guard let bindings = await Endpoint.sparql(query, attempts: 6, backoff: 20, log: note)
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
            // Three seconds, because 1.2 is what produced the truncation above. This is run
            // by hand against shared infrastructure; the extra minute is not worth an abort.
            await Endpoint.pause(3)
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
    // Romanised names, fetched after the per-language pass so a resume finds the languages
    // already on disk and only this is left to do.
    for (code, languages) in WikidataQueries.romanisedNameLocales where out[code] == nil {
        var kinds: [(key: String, value: OrderedJSON)] = []

        for (kind, classID) in WikidataQueries.nameClasses {
            let query = WikidataQueries.romanisedNameQuery(class: classID, languages: languages)
            guard let bindings = await Endpoint.sparql(query, attempts: 6, backoff: 20, log: note)
            else {
                fail(
                    "\(code) \(kind): endpoint gave up after retries. Re-run to resume — do "
                        + "not commit a snapshot with a category missing, it reads as an "
                        + "absence of data.")
            }

            let labels = bindings.compactMap { Endpoint.value($0, "l") }
            // Latin only. The label is *tagged* English, which is not the same as being
            // written in Latin script — a handful carry the native spelling under an `en`
            // tag, and one Devanagari surname in a romanised pool is the mixed-script bug
            // this corpus has already shipped once.
            let latin = labels.filter { value in
                value.unicodeScalars.contains { $0.properties.isAlphabetic }
                    && value.unicodeScalars.allSatisfy { scalar in
                        !scalar.properties.isAlphabetic || (0x0041...0x024F).contains(scalar.value)
                    }
            }
            let kept = Endpoint.distinctSorted(latin.filter(Endpoint.usable))
            if kept.count >= WikidataQueries.minimumNames {
                kinds.append((kind, .array(kept.map(OrderedJSON.string))))
            }
            note("\(code) \(kind): \(kept.count) of \(labels.count) (romanised)")
            await Endpoint.pause(3)
        }

        if !kinds.isEmpty {
            order.append(code)
            out[code] = .object(kinds)
            write(
                name,
                .object([
                    ("retrieved", .string(retrieved)),
                    ("names", .object(order.map { ($0, out[$0]!) })),
                ]))
        }
    }

    note("\nwrote \(order.count) locales")
}

// MARK: - Wikidata colours

/// Noun lemmas per language, from Wikidata's lexemes.
///
/// Same endpoint and the same resume-from-disk behaviour as the colour fetch. The floor is
/// applied here so a language below it is simply absent from the snapshot, which reads the
/// same as "Wikidata has nothing" — the distinction is kept in the log line, which reports
/// what came back before the floor was applied.
func wikidataLexemes() async {
    let name = "wikidata-lexemes"

    var order: [String] = []
    var out: [String: OrderedJSON] = [:]
    if let data = try? Data(
        contentsOf: dataDirectory.appendingPathComponent("\(name).json")),
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let words = root["nouns"] as? [String: [String]]
    {
        for (code, _) in WikidataQueries.lexemeLanguages where words[code] != nil {
            order.append(code)
            out[code] = .array(words[code]!.map(OrderedJSON.string))
        }
        if !order.isEmpty { note("resuming; \(order.count) locales already fetched") }
    }

    // One request per language, not per locale: `pt_BR` and `pt_PT` ask the same question.
    var languages: [String] = []
    var codesFor: [String: [String]] = [:]
    for (code, id) in WikidataQueries.lexemeLanguages {
        if codesFor[id] == nil { languages.append(id) }
        codesFor[id, default: []].append(code)
    }

    for id in languages {
        let codes = codesFor[id] ?? []
        if codes.allSatisfy({ out[$0] != nil }) { continue }

        guard
            let bindings = await Endpoint.sparql(
                WikidataQueries.lexemeQuery(language: id), attempts: 6, backoff: 20, log: note)
        else {
            // Not written as absent. A language that could not be fetched and one that has
            // nothing look identical in the snapshot, and that conflation is how Spanish
            // surnames were recorded as non-existent for months.
            fail(
                "\(codes.joined(separator: ", ")): endpoint gave up after retries. Re-run to "
                    + "resume — do not commit a snapshot with a language missing, it reads as "
                    + "an absence of data.")
        }

        let lemmas = bindings.compactMap { Endpoint.value($0, "lemma") }
        let kept = Endpoint.distinctSorted(lemmas.filter(Endpoint.usable))
        note("\(id): \(kept.count) of \(lemmas.count) -> \(codes.joined(separator: ", "))")

        if kept.count >= WikidataQueries.minimumLexemes {
            for code in codes {
                if out[code] == nil { order.append(code) }
                out[code] = .array(kept.map(OrderedJSON.string))
            }
        }

        write(
            name,
            .object([
                ("retrieved", .string(retrieved)),
                ("nouns", .object(order.map { ($0, out[$0]!) })),
            ]))
        await Endpoint.pause(3)
    }
    note("\nwrote \(order.count) locales")
}

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

// MARK: - Dispatch

/// Every snapshot, all of which `all` runs.
///
/// There used to be a second list for snapshots needing something from the person running
/// them — a key, a table identifier — which `all` deliberately skipped so one missing
/// credential could not fail the whole run. Nothing needs that now. Bring the split back
/// rather than folding such a snapshot in here.
let known = [
    "wikidata-names", "wikidata-colours", "wikidata-terms", "wikidata-lexemes",
    "statistics-names",
]
guard arguments.count > 1 else {
    fail("name a snapshot to fetch: \(known.joined(separator: ", ")), or all")
}

let requested = arguments[1] == "all" ? known : [arguments[1]]
for choice in requested where !known.contains(choice) {
    fail("unknown snapshot '\(choice)' — expected one of \(known.joined(separator: ", "))")
}

for choice in requested {
    note("=== \(choice)")
    switch choice {
    case "wikidata-names": await wikidataNames()
    case "wikidata-colours": await wikidataColours()
    case "wikidata-lexemes": await wikidataLexemes()
    case "wikidata-terms": await wikidataTerms()
    default: await statisticsNames()
    }
}
