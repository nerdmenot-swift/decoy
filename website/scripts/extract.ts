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
import { existsSync, mkdirSync, writeFileSync } from 'node:fs'
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
