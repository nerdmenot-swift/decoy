/**
 * Fetches given-name counts from statistical offices that answer a query rather than
 * publish a file, and writes them to `data/statistics-names.json`.
 *
 * Run by hand, not by the build:
 *
 *     node Tools/adapters/fetch-statistics-names.mjs
 *
 * Every other national register in `civil-names.mjs` is a file at a URL with an integrity
 * hash, which is what makes a silently changed upstream fail the build instead of quietly
 * altering everyone's fixtures. Norway and Slovenia publish through PxWeb instead: the
 * data comes back from a POST, so there is no file to hash and no version to pin.
 *
 * So the same arrangement as the Wikidata fetchers -- query once, deliberately, commit the
 * result beside the query that produced it. Anyone can re-run this and diff, which is a
 * stronger guarantee than a hash over somebody else's server because it can be checked by
 * inspection rather than only by comparison.
 *
 * ## The two are not the same shape, and neither is obvious
 *
 * Norway returns one table with both sexes in it, distinguished by a prefix on the code
 * rather than by a dimension: `1EMMA` is female Emma and `2JAKOB` is male Jakob. Nothing
 * in the response says so. Slovenia returns two tables, one per sex, each with the names
 * in a dimension of its own.
 *
 * Norway is queried as json-stat2 rather than CSV for a concrete reason: its CSV mangles
 * `Ø` to `Z2` and `Å` to `Z3`, which would silently corrupt every Norwegian name
 * containing them. Slovenia's CSV is windows-1250 for the same class of reason.
 */

import { mkdir, writeFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))

const AGENT = 'DecoyCorpusBuild/1.0 (https://github.com/NerdMeNot/decoy)'

/** The most recent year each source publishes, asked for explicitly so a re-run is stable. */
const NORWAY_YEAR = '2025'

async function ask(url, body) {
  for (let attempt = 0; attempt < 4; attempt++) {
    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'User-Agent': AGENT },
        body: JSON.stringify(body),
      })
      if (response.ok) return await response.json()
    } catch {
      // Truncated body, reset connection, or malformed JSON. All retryable.
    }
    await new Promise((resolve) => setTimeout(resolve, 4000 * (attempt + 1)))
  }
  return null
}

/**
 * Norway: one table, both sexes, sex encoded as the first character of the code.
 *
 * Only names held by 200 or more people are published at all, which is Statistics Norway
 * protecting individuals rather than a sampling choice, and sits at exactly the threshold
 * `civil-names.mjs` applies anyway.
 */
async function norway() {
  const data = await ask('https://data.ssb.no/api/v0/en/table/10501', {
    query: [
      { code: 'ContentsCode', selection: { filter: 'item', values: ['Personer'] } },
      { code: 'Tid', selection: { filter: 'item', values: [NORWAY_YEAR] } },
    ],
    response: { format: 'json-stat2' },
  })
  if (!data) return null

  const dimension = data.dimension?.Fornavn
  const labels = dimension?.category?.label
  const index = dimension?.category?.index
  if (!labels || !index) throw new Error('SSB response has no Fornavn dimension')

  const rows = []
  for (const [code, label] of Object.entries(labels)) {
    const count = data.value[index[code]]
    if (!Number.isFinite(count) || count <= 0) continue
    const sex = code.startsWith('1') ? 'female' : code.startsWith('2') ? 'male' : null
    if (!sex) continue
    rows.push({ name: label, sex, count })
  }
  return rows
}

/**
 * Slovenia: two tables, one per sex, each a name dimension crossed with years.
 *
 * The latest year is taken rather than summed. Slovenia publishes a stock -- how many
 * people hold the name *now* -- once per year, so adding the years together would count
 * the same living person once per year they were alive.
 */
async function slovenia() {
  const tables = [
    ['05X1005S', 'male'],
    ['05X1010S', 'female'],
  ]
  const rows = []
  for (const [table, sex] of tables) {
    const data = await ask(`https://pxweb.stat.si/SiStatData/api/v1/en/Data/${table}.px`, {
      query: [{ code: 'MERITVE', selection: { filter: 'item', values: ['1'] } }],
      response: { format: 'json-stat2' },
    })
    if (!data) return null

    const names = data.dimension?.IME
    const years = data.dimension?.LETO
    const labels = names?.category?.label
    const nameIndex = names?.category?.index
    const yearIndex = years?.category?.index
    if (!labels || !nameIndex || !yearIndex) throw new Error(`SURS ${table} has an unexpected shape`)

    const yearCount = Object.keys(yearIndex).length
    const latest = yearCount - 1

    for (const [code, label] of Object.entries(labels)) {
      // Row-major over (name, measure, year) with one measure selected, so a name's slice
      // is `yearCount` long and the last entry is the most recent year.
      const count = data.value[nameIndex[code] * yearCount + latest]
      if (!Number.isFinite(count) || count <= 0) continue
      rows.push({ name: label, sex, count })
    }
    await new Promise((resolve) => setTimeout(resolve, 1500))
  }
  return rows
}

const RETRIEVED = new Date().toISOString().slice(0, 10)
const out = {}

for (const [country, fetcher] of [['NO', norway], ['SI', slovenia]]) {
  const rows = await fetcher()
  if (rows === null) {
    process.stderr.write(`${country}: endpoint gave up\n`)
    continue
  }
  if (rows.length < 500) {
    throw new Error(`${country} returned only ${rows.length} names — verify before committing`)
  }
  out[country] = rows
  const female = rows.filter((row) => row.sex === 'female').length
  process.stderr.write(`${country}: ${rows.length} names (${female} female)\n`)
}

await mkdir(join(here, 'data'), { recursive: true })
await writeFile(
  join(here, 'data', 'statistics-names.json'),
  JSON.stringify({ retrieved: RETRIEVED, countries: out }, null, 1),
)
process.stderr.write(`\nwrote ${Object.keys(out).length} countries\n`)
