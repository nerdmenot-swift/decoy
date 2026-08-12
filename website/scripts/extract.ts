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

const HERE = dirname(fileURLToPath(import.meta.url))
const REPO = join(HERE, '..', '..')
const CORPUS = join(REPO, 'Corpus', 'binary')
const OUT = join(HERE, '..', 'src', 'data')

/** Locales shown in the "one person, many locales" panel. Chosen to span scripts and
 *  to include two that fall back, because the fallback is part of the story. */
const TOUR = ['en', 'de', 'fr', 'es', 'it', 'ja', 'ru', 'pl', 'tr', 'he', 'zh_CN', 'vi']

/** Chains mirror the rule in run.mjs: strip trailing segments, then en, then base. */
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

const SWIFT = (locales: Record<string, string[]>) => `
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
    ("name", "person.last_name.generic"), ("city", "location.city_name"),
    ("company", "company.name_pattern"), ("job", "person.job_title"),
    ("phone", "phone_number.format.national"),
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
struct Payload: Encodable { let locales: [String: [String: [Row]]]; let fun: [String: [String]]; let prov: [String: [String: Prov]] }
FileHandle.standardOutput.write(try! enc.encode(Payload(locales: out, fun: fun, prov: prov)))
`

if (!existsSync(join(CORPUS, 'en.decoy'))) {
  console.log('  extract: no compiled corpus — keeping existing src/data, see Corpus/binary')
  process.exit(0)
}

const locales = Object.fromEntries(TOUR.map((c) => [c, chainFor(c)]))
const tmp = join(REPO, '.website-extract')
mkdirSync(join(tmp, 'Sources', 'extract'), { recursive: true })
writeFileSync(join(tmp, 'Sources', 'extract', 'main.swift'), SWIFT(locales))
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
writeFileSync(join(OUT, 'samples.json'), JSON.stringify(payload, null, 2))
console.log(
  `  extract: ${Object.keys(payload.locales).length} locales × 3 seeds, ` +
    `${Object.keys(payload.fun).length} whimsy generators`
)

// ---------------------------------------------------------------------------
// Generated reference pages
// ---------------------------------------------------------------------------
//
// Three pages are written from the source rather than by hand, because a hand-kept
// list of 315 methods is a list that is correct on the day it is written. The counts
// in this repository have drifted three times already; a generator cannot drift.

const DOCS = join(HERE, '..', 'src', 'content', 'docs', 'reference')
const GENERATORS = join(REPO, 'Sources', 'Decoy', 'Generators')

/** Every `public [mutating] func` inside each `public struct …Faker`. */
function surface(): Map<string, string[]> {
  const found = new Map<string, string[]>()
  for (const file of readdirSync(GENERATORS).filter((f) => f.endsWith('.swift'))) {
    const src = readFileSync(join(GENERATORS, file), 'utf8')
    let current: string | null = null
    for (const line of src.split('\n')) {
      const struct = line.match(/^\s*public struct ([A-Za-z]+)Faker\b/)
      if (struct) {
        current = struct[1][0].toLowerCase() + struct[1].slice(1)
        if (!found.has(current)) found.set(current, [])
        continue
      }
      const fn = line.match(/^\s*public (?:mutating )?func ([a-z][A-Za-z0-9]*)\s*\(/)
      if (fn && current) found.get(current)!.push(fn[1])
    }
  }
  return found
}

const NAMESPACE_NOTES: Record<string, string> = {
  location: 'Cities, addresses, postcodes, subdivisions, coordinates.',
  whimsy: 'Invented things — pubs, bands, codenames, technobabble.',
  internet: 'Emails, domains, user agents, passwords, colours.',
  instant: 'Timestamps without Foundation.',
  date: 'The same, as `Foundation.Date`. Compiled only where Foundation exists.',
  person: 'Names, honorifics, jobs, zodiac.',
  system: 'Files, MIME types, semver, error messages.',
  finance: 'IBANs, cards, currencies, transactions.',
  notable: 'Historical figures and a short list of public ones.',
  commerce: 'Products, departments, reviews.',
  beverage: 'Invented beer, wine, whisky, coffee, tea.',
  food: 'Real produce, cheeses, dishes, breads.',
  company: 'Names, legal forms, buzzwords.',
  media: 'Books, films, songs, genres, instruments.',
  animal: 'Animals, birds, breeds, insects, pet names.',
  nature: 'Mountains, rivers, lakes, islands, trees, gemstones.',
  word: 'Parts of speech, from wordnets.',
  vehicle: 'Manufacturers, models, plates, VINs.',
  lorem: 'Placeholder prose, in Latin.',
  crypto: 'Hashes and checksummed chain addresses.',
  brand: 'Cameras, phones, watches, appliances.',
  airline: 'Airports, aircraft, flight numbers, seats.',
  sport: 'Invented clubs, venues, trophies; real disciplines.',
  institution: 'Universities, clubs, museums, newspapers.',
  color: 'Human names, hex, RGB, colour spaces.',
  phone: 'Numbers in each locale’s own format, IMEI.',
  database: 'Engines, collations, column types.',
  science: 'Chemical elements and SI units.',
}

function writeNamespaces() {
  const api = [...surface().entries()].sort((a, b) => b[1].length - a[1].length)
  const total = api.reduce((n, [, m]) => n + m.length, 0)
  const body = api
    .map(([ns, methods]) => {
      const notes = NAMESPACE_NOTES[ns] ? `\n${NAMESPACE_NOTES[ns]}\n` : '\n'
      return `### \`${ns}\` · ${methods.length}\n${notes}\n` +
        methods.map((m) => `\`${m}()\``).join(' · ')
    })
    .join('\n\n')
  writeFileSync(join(DOCS, 'namespaces.md'),
`---
title: Namespaces
description: Every generator Decoy ships, grouped by namespace.
---

<!-- Generated by website/scripts/extract.ts. Do not edit by hand. -->

${total} generators across ${api.length} namespaces. Every one is seeded and reproducible:
the same seed and corpus version always give the same value.

Reach them through a \`Faker\`:

\`\`\`swift
var faker = Faker(seed: 1337, locale: DecoyLocaleEN.locale)
faker.person.fullName()
faker.location.placeAndPostcode()
\`\`\`

${body}
`)
  return { total, count: api.length }
}

function writeSources() {
  const dir = join(REPO, 'Tools', 'adapters', 'sources')
  const rows = readdirSync(dir).filter((f) => f.endsWith('.json')).map((f) => {
    const s = JSON.parse(readFileSync(join(dir, f), 'utf8'))
    const name = s.url ? `[${s.name}](${s.url})` : s.name
    return `| \`${s.id}\` | ${name} | \`${s.license}\` | ${s.retrieved || s.version || '—'} |`
  }).sort()
  writeFileSync(join(DOCS, 'sources.md'),
`---
title: Sources
description: Every source the corpus is built from, with its licence and retrieval date.
---

<!-- Generated by website/scripts/extract.ts. Do not edit by hand. -->

${rows.length} sources. Each is fetched from a pinned URL and verified against an SRI
integrity hash, so a silently changed upstream fails the build rather than quietly
altering everyone's fixtures. Licences are checked mechanically on every run against an
Apache-2.0 compatibility list.

A cached artifact is re-verified rather than trusted: a tampered cache would otherwise
produce a corpus that passes every check on the machine that built it and nowhere else.

| ID | Source | Licence | Retrieved |
|---|---|---|---|
${rows.join('\n')}

Two licence values are not SPDX identifiers and mean something specific.
**\`public-facts\`** records a conclusion: the extracted content is facts nobody authored —
that Antigua and Barbuda has the ISO code \`AG\`, that a German GmbH is abbreviated so
because statute says it is — and there is no creative expression for anyone to license.
**\`public-domain\`** is a positive statement by the publisher.

Every source with a licence requiring its notice to travel also ships that notice in
\`LICENSES/\`, and \`decoy-inspect --notice\` fails if one is about to be named without it.
`)
  return rows.length
}

function writeMatrix() {
  const md = readFileSync(join(REPO, 'docs', 'locale-support.md'), 'utf8')
  const table = md.slice(md.indexOf('| Locale |'))
  writeFileSync(join(DOCS, 'locale-matrix.md'),
`---
title: Locale matrix
description: What each locale supplies itself, and what it borrows.
---

<!-- Generated by website/scripts/extract.ts from docs/locale-support.md. Do not edit. -->

A locale either supplies a field itself, or resolves it through the fallback chain — in
which case the values are **another language's**, almost always English.

\`N\` means the locale carries its own data for that group. \`·\` means it inherits.

Generated from the compiled corpus and diffed in CI, so it cannot describe a corpus that
is no longer shipping.

${table}

## Reading it

A group is only as native as its weakest member: *Given names* needs both the female and
male lists, so a locale carrying one and not the other reads as inherited.

The last two columns behave differently from the rest. **Invented names** and
**Real-world lists** are English-only by design and show a single native locale between
them, so they are excluded from the coverage percentage — counting content that will
never be translated would measure how much has been invented rather than how local a
locale is. They appear here because a caller reaching for an animal name really does get
English, and a table that omitted the row would read as *not offered*.
`)
}

const ns = writeNamespaces()
const srcCount = writeSources()
writeMatrix()
console.log(`  extract: ${ns.total} methods / ${ns.count} namespaces, ${srcCount} sources, matrix`)
