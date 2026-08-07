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
 */

import { readFile } from 'node:fs/promises'
import { join } from 'node:path'

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
      },
    },
    stats: {
      surnames: values.length,
      belowThreshold: dropped,
      mostCommon: `${values[0]} (${weights[0].toLocaleString('en-US')})`,
    },
  }
}
