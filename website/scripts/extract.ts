/**
 * Pulls real data out of the library so the site never has to invent any.
 *
 *     bun run scripts/extract.ts
 *
 * Decoy is deterministic, which means every demo on this site can be *actual* output
 * rather than a mock-up: build a tiny Swift program against the real corpus, run it,
 * and write the results to JSON the pages import. Nothing is faked, no WASM is shipped,
 * and there is no runtime cost — the interactivity is replaying a recording of the
 * genuine article.
 *
 * If the corpus is not compiled the script says so and leaves any previous output in
 * place, so `astro dev` still works on a fresh clone without a Swift toolchain.
 */

import { $ } from 'bun'
import { existsSync, mkdirSync, writeFileSync, readFileSync, readdirSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { readSurface, key, call } from './parse'

const HERE = dirname(fileURLToPath(import.meta.url))
const REPO = join(HERE, '..', '..')
const CORPUS = join(REPO, 'Corpus', 'binary')
const OUT = join(HERE, '..', 'src', 'data')

/** Locales shown in the "one person, many locales" panel. Chosen to span scripts and
 *  to include two that fall back, because the fallback is part of the story. */
const TOUR = ['en', 'de', 'fr', 'es', 'it', 'ja', 'ru', 'pl', 'tr', 'he', 'zh_CN', 'vi']

/** Chains mirror `Orchestrator.fallbackChain`: strip trailing segments, then en, then base. */
function chainFor(code: string): string[] {
  const parts: string[] = [code]
  let rest = code
  while (rest.includes('_')) {
    rest = rest.slice(0, rest.lastIndexOf('_'))
    parts.push(rest)
  }
  for (const tail of ['en', 'base']) if (!parts.includes(tail)) parts.push(tail)
  return parts.filter((c) => existsSync(join(CORPUS, `${c}.decoy`)))
}

const SWIFT = (locales: Record<string, string[]>, probes: string) => `
import Decoy
import Foundation

let dir = "${CORPUS}"
func load(_ code: String, _ chain: [String]) -> LocaleCorpus {
    LocaleCorpus(code: code, chain: chain.map {
        try! Corpus(bytes: [UInt8](try! Data(contentsOf:
            URL(fileURLWithPath: "\\(dir)/\\($0).decoy"))))
    })
}

struct Row: Encodable {
    let name: String, email: String, city: String, address: String
    let phone: String, company: String, job: String, product: String
}

func rows(_ locale: LocaleCorpus, seed: UInt64, count: Int) -> [Row] {
    (0..<count).map { i in
        var f = Faker(seed: seed &+ UInt64(i), locale: locale)
        return Row(
            name: f.person.fullName(),
            email: f.internet.email(),
            city: f.location.city(),
            address: f.location.streetAddress(),
            phone: f.phone.number(),
            company: f.company.name(),
            job: f.person.jobTitle(),
            product: f.commerce.productName()
        )
    }
}

/// Everything stringifies the same way, so tuples, dictionaries, numbers and dates
/// all reach the reference without a special case per return type.
///
/// Dictionaries are sorted by key first. Swift's Dictionary is unordered and its Hasher is
/// seeded per process, so \`String(describing:)\` prints the same dictionary in a different
/// order on each run -- which made every regeneration of these pages produce a diff with
/// no change in it. Sorting is the difference between documentation that is diffable and
/// documentation that merely churns.
func s<T>(_ v: T) -> String {
    if let v = v as? String { return v }
    if let d = v as? [String: String] {
        return "[" + d.sorted { $0.key < $1.key }
            .map { "\\"\\($0.key)\\": \\"\\($0.value)\\"" }
            .joined(separator: ", ") + "]"
    }
    return String(describing: v)
}
func mk(_ seed: UInt64) -> Faker { Faker(seed: seed, locale: load("en", ["en", "base"])) }

/// Up to three *distinct* values, where the pool allows it.
///
/// Three consecutive seeds and whatever falls out put visible duplicates through the whole
/// reference -- firstName() showing "Mary, Mary, Janet" reads as a bug rather than as a
/// small pool. Fewer than three is returned honestly when the pool really is that small,
/// which is information rather than an omission.
func distinct(_ seed: UInt64, _ body: (inout Faker) -> String) -> [String] {
    var out: [String] = []
    for k in 0..<24 {
        var f = mk(seed &+ UInt64(k))
        let v = body(&f)
        if !out.contains(v) { out.append(v) }
        if out.count == 3 { break }
    }
    return out
}
var api: [String: [String]] = [:]
${probes}

var out: [String: [String: [Row]]] = [:]
${Object.entries(locales)
  .map(
    ([code, chain]) => `
do {
    let loc = load("${code}", ${JSON.stringify(chain)})
    out["${code}"] = ["1337": rows(loc, seed: 1337, count: 6),
                      "2024": rows(loc, seed: 2024, count: 6),
                      "7":    rows(loc, seed: 7, count: 6)]
}`
  )
  .join('')}

// Whimsy, which is the part people will actually play with.
var fun: [String: [String]] = [:]
do {
    let en = load("en", ["en", "base"])
    var f = Faker(seed: 99, locale: en)
    // A plain loop rather than \`map\`: under Swift 6 the closure would be captured by a
    // main-actor-isolated one and the compiler rejects it as a data race.
    func take(_ n: Int, _ body: (inout Faker) -> String) -> [String] {
        var out: [String] = []
        for _ in 0..<n { out.append(body(&f)) }
        return out
    }
    fun["pubName"] = take(8) { $0.whimsy.pubName() }
    fun["bandName"] = take(8) { $0.whimsy.bandName() }
    fun["boardGame"] = take(8) { $0.whimsy.boardGame() }
    fun["beer"] = take(8) { $0.beverage.beer() }
    fun["whisky"] = take(8) { $0.beverage.whisky() }
    fun["club"] = take(8) { $0.sport.club() }
    fun["talkTitle"] = take(6) { $0.whimsy.talkTitle() }
    fun["excuse"] = take(6) { $0.whimsy.excuse() }
    fun["codename"] = take(8) { $0.whimsy.codename() }
    fun["restaurantName"] = take(8) { $0.whimsy.restaurantName() }
    fun["dishName"] = take(6) { $0.whimsy.dishName() }
    fun["technobabble"] = take(4) { $0.whimsy.technobabble() }
    fun["databaseError"] = take(5) { $0.system.databaseError() }
    fun["review"] = take(4) { $0.commerce.review() }
    fun["superheroName"] = take(8) { $0.whimsy.superheroName() }
    fun["ssid"] = take(6) { $0.whimsy.ssid() }
}

// Provenance for the columns the register shows. The whole argument of the project is
// that every value can name its source, so the site had better read that out of the
// corpus rather than caption it by hand.
struct Prov: Encodable { let path: String, source: String, license: String, version: String, retrieved: String }
var prov: [String: [String: Prov]] = [:]
let COLUMNS = [
    ("name", "person.last_name.generic"), ("address", "location.street_address.normal"),
    ("city", "location.city_name"), ("company", "company.name_pattern"),
    ("job", "person.job_title"), ("phone", "phone_number.format.national"),
]

func provenance(_ loc: LocaleCorpus) -> [String: Prov] {
    var byColumn: [String: Prov] = [:]
    for (column, path) in COLUMNS {
        // Walk the chain the way a draw does, so the credited source is the one that
        // actually supplied this locale's value rather than the first that mentions it.
        for corpus in loc.chain {
            guard let entry = try? corpus.lookup(path), case .strings(let t) = entry,
                let s = try? corpus.source(t.sourceID) else { continue }
            byColumn[column] = Prov(path: path, source: s.id, license: s.license,
                                    version: s.version, retrieved: s.retrieved)
            break
        }
    }
    return byColumn
}
${Object.entries(locales)
  .map(([code, chain]) => `prov["${code}"] = provenance(load("${code}", ${JSON.stringify(chain)}))`)
  .join('\n')}

let enc = JSONEncoder()
enc.outputFormatting = [.prettyPrinted, .sortedKeys]
struct Payload: Encodable { let locales: [String: [String: [Row]]]; let fun: [String: [String]]; let prov: [String: [String: Prov]]; let api: [String: [String]] }
FileHandle.standardOutput.write(try! enc.encode(Payload(locales: out, fun: fun, prov: prov, api: api)))
`

if (!existsSync(join(CORPUS, 'en.decoy'))) {
  console.log('  extract: no compiled corpus — keeping existing src/data, see Corpus/binary')
  process.exit(0)
}

const locales = Object.fromEntries(TOUR.map((c) => [c, chainFor(c)]))
const tmp = join(REPO, '.website-extract')
mkdirSync(join(tmp, 'Sources', 'extract'), { recursive: true })
const surface = readSurface(join(REPO, 'Sources', 'Decoy', 'Generators'))
let probeSeed = 1000
const probes = surface
  .filter((m) => m.callable)
  .map((m) => {
    const line = `api["${key(m)}"] = distinct(${probeSeed}) { f in s(${call(m)}) }`
    // Stride wider than the three values wanted, so the dedup window of one generator
    // cannot overlap the seeds of the next.
    probeSeed += 24
    return line
  })
  .join('\n')
writeFileSync(join(tmp, 'Sources', 'extract', 'main.swift'), SWIFT(locales, probes))
writeFileSync(
  join(tmp, 'Package.swift'),
  `// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "extract",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "${REPO}")],
    targets: [.executableTarget(name: "extract",
        dependencies: [.product(name: "Decoy", package: "decoy")])]
)
`
)

console.log('  extract: building against the real corpus…')
const json = await $`swift run -c release --package-path ${tmp} extract`.quiet().text()

mkdirSync(OUT, { recursive: true })
const payload = JSON.parse(json)
console.log(
  `  extract: ${Object.keys(payload.locales).length} locales × 3 seeds, ` +
    `${Object.keys(payload.fun).length} whimsy generators`
)

// ---------------------------------------------------------------------------
// Generated reference pages
// ---------------------------------------------------------------------------
//
// One page per namespace, every method listed with output the library actually
// produced during this build. Hand-written examples go stale silently; these cannot.

const DOCS = join(HERE, '..', 'src', 'content', 'docs')
const API_DIR = join(DOCS, 'api')

/** What each namespace is for, in one line, shown on its page and in the index. */
const ABOUT: Record<string, string> = {
  person: 'Names, honorifics, job titles, gender, zodiac.',
  location: 'Addresses, cities, subdivisions, postcodes, coordinates, countries.',
  internet: 'Emails, usernames, domains, URLs, IPs, user agents, passwords.',
  company: 'Company names, legal forms, catchphrases, buzzwords.',
  commerce: 'Products, departments, prices, SKUs, barcodes, reviews.',
  finance: 'IBANs, card numbers, account numbers, currencies, transactions.',
  phone: 'Numbers in each locale’s own format, area codes, IMEI.',
  instant: 'Dates and times as `Timestamp`, with no Foundation dependency.',
  date: 'The same values as `Foundation.Date`. Only where Foundation exists.',
  system: 'File names and paths, MIME types, semver, error messages.',
  database: 'Engines, collations, column names and types.',
  crypto: 'Hashes and checksummed blockchain addresses.',
  lorem: 'Placeholder prose, in Latin.',
  word: 'Single words by part of speech, from wordnets.',
  color: 'Human colour names, hex, RGB, colour spaces.',
  science: 'Chemical elements and SI units.',
  vehicle: 'Manufacturers, models, fuel types, plates, VINs.',
  airline: 'Airports, aircraft, flight numbers, seats, record locators.',
  animal: 'Animals, birds, fish, insects, breeds, pet names.',
  food: 'Fruit, vegetables, cheeses, dishes, breads, seafood.',
  nature: 'Mountains, rivers, lakes, islands, trees, flowers, gemstones, weather.',
  media: 'Book, film and song titles, authors, genres, instruments.',
  notable: 'Historical figures, plus a short list of living public ones.',
  brand: 'Cameras, phones, watches, fashion, sportswear, appliances.',
  institution: 'Universities, football clubs, museums, newspapers, orchestras.',
  whimsy: 'Invented pubs, bands, codenames, superheroes, technobabble.',
  beverage: 'Invented beers, wines, whiskies, cocktails, coffees, teas.',
  sport: 'Invented clubs, venues and trophies; real disciplines.',
}

/** Namespaces whose values are invented, or real-but-unverified. Flagged on the page
 *  so nobody ships one believing it carries the same guarantee as a sourced field. */
const CAVEAT: Record<string, string> = {
  whimsy: 'invented',
  beverage: 'invented',
  sport: 'invented',
  animal: 'unverified',
  food: 'unverified',
  nature: 'unverified',
  media: 'unverified',
  notable: 'unverified',
  brand: 'unverified',
  institution: 'unverified',
}

const NOTE: Record<string, string> = {
  invented:
    ':::note[Invented]\nValues here are composed, not sourced. There is no fact of the ' +
    'matter for them to be wrong about — which is exactly why they are allowed.\n:::',
  unverified:
    ':::caution[High accuracy, unverified]\nThese are real things, written from general ' +
    'knowledge rather than fetched from a registry. Every other source in the corpus is ' +
    'pinned and hash-verified; this one cannot be.\n:::',
}

function escapeCell(v: string) {
  return v.replace(/\|/g, '\\|').replace(/\n/g, ' ').slice(0, 90)
}

function writeApiPages(api: Record<string, string[]>) {
  const surface = readSurface(join(REPO, 'Sources', 'Decoy', 'Generators'))
  const byNs = new Map<string, typeof surface>()
  for (const m of surface) {
    const ns = m.ns || 'faker'
    if (!byNs.has(ns)) byNs.set(ns, [])
    byNs.get(ns)!.push(m)
  }

  mkdirSync(API_DIR, { recursive: true })
  const index: string[] = []

  for (const [ns, methods] of [...byNs.entries()].sort()) {
    const accessor = ns === 'faker' ? 'faker' : `faker.${ns}`
    const rows = methods
      .map((m) => {
        const signature = `${m.name}(${escapeCell(m.params)})`
        const examples = api[key(m)]
        const shown = examples?.length
          ? examples.map((e) => `\`${escapeCell(e)}\``).join('<br />')
          : '_needs arguments_'
        return `| \`${signature}\` | ${shown} |`
      })
      .join('\n')

    const caveat = CAVEAT[ns] ? `\n${NOTE[CAVEAT[ns]]}\n` : ''
    writeFileSync(join(API_DIR, `${ns}.md`),
`---
title: ${ns}
description: ${ABOUT[ns] ?? `The \`${ns}\` generators.`}
---

<!-- Generated by website/scripts/extract.ts. Do not edit by hand. -->

${ABOUT[ns] ?? ''}
${caveat}
\`\`\`swift
var faker = Faker(seed: 1337, locale: DecoyLocaleEN.locale)
${accessor}.${methods[0].name}()
\`\`\`

| Method | Example output |
|---|---|
${rows}

Examples are real output from three different seeds, captured when this page was built,
using each method's **default** arguments. Where a signature shows parameters, pass your
own to change the size, gender, length or format.
`)
    index.push(`| [\`${ns}\`](/api/${ns}/) | ${methods.length} | ${ABOUT[ns] ?? ''} |`)
  }

  const total = surface.length
  writeFileSync(join(API_DIR, 'index.md'),
`---
title: All generators
description: Every generator Decoy ships, grouped by namespace.
---

<!-- Generated by website/scripts/extract.ts. Do not edit by hand. -->

${total} generators across ${byNs.size} namespaces. Each page lists every method with
output the library actually produced.

\`\`\`swift
import Decoy
import DecoyLocaleEN

var faker = Faker(seed: 1337, locale: DecoyLocaleEN.locale)
faker.person.fullName()      // "Riley Bonneau"
faker.location.city()        // "Duchesne"
\`\`\`

| Namespace | Methods | |
|---|---|---|
${index.join('\n')}
`)
  return { total, count: byNs.size }
}

function writeSources() {
  const dir = join(REPO, 'Tools', 'adapters', 'sources')
  // Counted rather than asserted, because the split moves: five of the forty-nine have no
  // pinned artifact at all — two are written here, three answer a query and have their
  // result committed instead. Saying "each is fetched from a pinned URL" was wrong for all
  // five.
  const descriptors = readdirSync(dir).filter((f) => f.endsWith('.json'))
    .map((f) => JSON.parse(readFileSync(join(dir, f), 'utf8')))
  const pinned = descriptors.filter((s) => (s.artifacts || []).length > 0).length
  // Derived too, and for the reason above rather than a different one. The prose below
  // used to say "three answer a query" and "two are written here" as literals while the
  // *total* was computed, so adding the Korean statistics office made the paragraph
  // contradict its own first sentence: six remaining, three plus two explained.
  //
  // `authored: true` is not the discriminator: it marks "no pinned artifact", which is
  // true of both kinds. What separates them is where the descriptor points — a source
  // written here cites this repository, because that is literally where it was written.
  const REPO_URL = 'https://github.com/nerdmenot-swift/decoy'
  const unpinned = descriptors.filter((s) => !(s.artifacts || []).length)
  const authored = unpinned.filter((s) => s.url === REPO_URL)
  const queried = unpinned.filter((s) => s.url !== REPO_URL)
  const list = (names) =>
    names.length < 2 ? names.join('')
      : `${names.slice(0, -1).join(', ')} and ${names[names.length - 1]}`
  const count = (n) =>
    ['no', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight'][n] ?? String(n)
  const rows = descriptors.map((s) => {
    const name = s.url ? `[${s.name}](${s.url})` : s.name
    return `| \`${s.id}\` | ${name} | \`${s.license}\` | ${s.retrieved || s.version || '—'} |`
  }).sort()
  writeFileSync(join(DOCS, 'reference', 'sources.md'),
`---
title: Sources
description: Every source the corpus is built from, with licence and retrieval date.
---

<!-- Generated by website/scripts/extract.ts. Do not edit by hand. -->

${rows.length} sources. ${pinned} are fetched from a pinned URL and verified against an SRI
integrity hash, so a changed upstream fails the build rather than quietly altering
everyone's fixtures.

The remaining ${rows.length - pinned} have no file to hash. ${count(queried.length)} answer a query rather than
publishing a file — ${list(queried.map((s) => '`' + s.id + '`'))} — so the query is run
deliberately with \`decoy-fetch\` and its result committed, which anyone can re-run and
diff. ${count(authored.length)} ${authored.length === 1 ? 'is' : 'are'} written here, and say so.

| ID | Source | Licence | Retrieved |
|---|---|---|---|
${rows.join('\n')}

\`public-facts\` and \`public-domain\` are not SPDX identifiers. The first records that the
extracted content is facts nobody authored — that Antigua and Barbuda has the ISO code
\`AG\` — and so has no author to license it. The second is a positive statement by the
publisher.
`)
  return rows.length
}

function writeMatrix() {
  const md = readFileSync(join(REPO, 'docs', 'locale-support.md'), 'utf8')
  const table = md.slice(md.indexOf('| Locale |'))
  // Data rows only: the header and its separator both start with a pipe too.
  const locales = table
    .split('\n')
    .filter((l) => l.startsWith('|') && !/^\|\s*(Locale|[-: ]+\|)/.test(l)).length
  writeFileSync(join(DOCS, 'reference', 'locale-matrix.md'),
`---
title: Locale matrix
description: What each locale supplies itself, and what it inherits.
---

<!-- Generated by website/scripts/extract.ts from docs/locale-support.md. Do not edit. -->

✓ means the locale carries its own data for that group. ✗ means it inherits from the
fallback chain — which almost always means English. A ✗ field still generates; it just
generates English.

Check this before picking a locale. Generated from the compiled corpus and diffed in CI.

${table}

The last two columns are English-only by design and excluded from coverage percentages.
They are shown because a caller reaching for an animal name really does get English.
`)
  return locales
}

const apiStats = writeApiPages(payload.api ?? {})
const srcCount = writeSources()
const localeCount = writeMatrix()

// The counts ship as data rather than as prose anybody has to remember to update. Three
// different generator totals were live on the site at once -- 319 on the reference index,
// 316 in the landing page headline, 315 in the README -- because each was typed by hand
// at a different time. `api` alone cannot supply it: it holds only the methods that
// produced a sample, so counting its keys silently understates the library by however many
// generators take required arguments.
payload.stats = {
  generators: apiStats.total,
  namespaces: apiStats.count,
  sources: srcCount,
  locales: localeCount,
}
writeFileSync(join(OUT, 'samples.json'), JSON.stringify(payload, null, 2))
console.log(
  `  extract: ${apiStats.total} methods / ${apiStats.count} namespaces, ` +
    `${srcCount} sources, matrix`
)
