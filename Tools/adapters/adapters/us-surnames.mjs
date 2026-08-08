/**
 * English surnames with real population frequencies, from the US Census.
 *
 * The first weighted table in the corpus, and the reason the format has carried a weight
 * column since v1. Every faker draws names uniformly; real surnames are Zipf-distributed,
 * with Smith about seventy times more common than the thousandth name. Uniform sampling
 * produces data that is wrong in exactly the way that matters for backend work —
 * deduplication and fuzzy-matching logic look flawless because real collision rates never
 * occur, and analytics built on it have suspiciously flat histograms.
 *
 * Fills:
 *   en    person.last_name.generic   weighted by 2010 Census counts
 *   en    person.last_name_model     an n-gram trained on the same names
 *
 * The list and the model do different jobs and both are kept. The list is what
 * `lastName()` draws, because its weights are the real population frequencies and no
 * model reproduces those. The model is what `lastName(novel:)` draws, because a list of
 * 24,889 names runs out under a `unique` rule at 24,889 rows and a model does not run out
 * at all.
 *
 * The model does *not* save space here, and the strategy doc used to claim it would.
 * Measured: at order 3 the model is 89 KB against the list's 182 KB but the output
 * degrades to `Rumboneczor` and `Garsterrever`; at order 4, where it produces `Newcomb`
 * and `Sigmann`, it is comparable to or larger than the list. Order 4 with `minCount: 2`
 * is the chosen point — the smallest model whose output reads as English surnames.
 */

import { readFile } from 'node:fs/promises'
import { join } from 'node:path'

import { bloomFilter, train } from '../lib/ngram.mjs'

export const id = 'us-surnames'
export const source = 'us-census-surnames'

/**
 * Surnames borne by at least this many people in the 2010 Census.
 *
 * A stated rule rather than a round number of rows. It keeps 24,889 names covering 85.8%
 * of the population; the Census publishes down to 100 occurrences, which would be 162,253
 * names and roughly a megabyte for a tail that a weighted draw would essentially never
 * reach — the 25,000th name is drawn about four times in a million rows.
 *
 * Truncation does not distort what remains: the weights kept are the real counts, so the
 * relative distribution among these names is exactly the Census's.
 */
const MINIMUM_BEARERS = 1000

/**
 * The Census publishes names in upper case; nobody stores them that way.
 *
 * Capitalises after each hyphen and apostrophe too, so `O'BRIEN` and `SMITH-JONES` come
 * back as `O'Brien` and `Smith-Jones` rather than `O'brien` and `Smith-jones`.
 */
function titleCase(name) {
  let out = ''
  let atBoundary = true
  for (const character of name.toLowerCase()) {
    out += atBoundary ? character.toUpperCase() : character
    atBoundary = character === '-' || character === "'" || character === ' '
  }
  return out
}

export async function run({ artifacts }) {
  const csv = await readFile(
    join(artifacts.surnames, 'Names_2010Census.csv'),
    'utf8',
  )

  const lines = csv.split('\n')
  const header = lines[0].split(',')
  const nameColumn = header.indexOf('name')
  const countColumn = header.indexOf('count')
  if (nameColumn < 0 || countColumn < 0) {
    throw new Error('Census file has no name/count columns — the schema has changed')
  }

  const values = []
  const weights = []
  let dropped = 0

  for (const line of lines.slice(1)) {
    const fields = line.split(',')
    if (fields.length <= countColumn) continue

    const name = fields[nameColumn]
    // A residual bucket, not a surname anybody is called.
    if (name === 'ALL OTHER NAMES') continue

    const count = Number(fields[countColumn])
    if (!Number.isFinite(count) || count <= 0) continue
    if (count < MINIMUM_BEARERS) {
      dropped += 1
      continue
    }

    values.push(titleCase(name))
    weights.push(count)
  }

  if (values.length < 10_000) {
    throw new Error(`Census file yielded only ${values.length} surnames — verify before re-pinning`)
  }

  // Trained on the names as types, one vote each. See lib/ngram.mjs for why the Census
  // counts are deliberately not used as training weights.
  const trained = train(values, { order: 4, minCount: 2 })
  const filter = bloomFilter(values, { falsePositiveRate: 0.01 })
  const model = {
    ...trained,
    filterHashCount: filter.hashCount,
    // Base64: the filter is 29 KB of bytes, which would be 100 KB of decimal digits and
    // commas in the intermediate JSON.
    filterBits: Buffer.from(filter.bits).toString('base64'),
  }

  return {
    // `en` rather than `en_US`: this is where faker's equivalent list lived, and `en` is
    // the chain every locale without its own surnames falls through to. Those locales
    // were already getting American surnames; now they get them in realistic proportions.
    contributions: {
      en: {
        'person.last_name.generic': values.map((value, i) => ({
          value,
          weight: weights[i],
        })),
        'person.last_name_model': { __model: model },
      },
    },
    stats: {
      surnames: values.length,
      belowThreshold: dropped,
      mostCommon: `${values[0]} (${weights[0].toLocaleString('en-US')})`,
      modelContexts: model.contexts.length,
      modelTransitions: model.contexts.reduce((n, c) => n + c.transitions.length, 0),
    },
  }
}
