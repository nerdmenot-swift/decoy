/**
 * Small closed concept sets per language, from Wikidata.
 *
 * Fills:
 *   <each>  location.direction.ordinal    northeast, northwest, southeast, southwest
 *   <each>  person.western_zodiac_sign    the twelve, in their conventional order
 *   <each>  person.sex                    male, female
 *
 * These are the paths in the corpus that are genuinely the same set everywhere and differ
 * only in what each language calls them. That is what makes them safe to take from a
 * multilingual label store: there is no judgement about which members a locale should
 * have, only about the words, and Wikidata is a good source of words.
 *
 * Contrast `color.human`, which is also from Wikidata and is not like this at all -- every
 * language names a different set of colours, and pretending otherwise is how translation
 * artefacts get in. The two adapters look similar and are doing different things.
 *
 * ## What a language must supply to be used
 *
 * All members or none. `fetch-wikidata-terms.mjs` enforces it: a language with nine of the
 * twelve signs has a translation in progress, and shipping the nine would give a zodiac
 * that silently lacks Capricorn. Absent is better, because the chain then falls back to a
 * complete English set instead of a plausible-looking partial one.
 *
 * **CC0**, so nothing to reconcile with Apache-2.0. See `sources/wikidata.json` for why the
 * query results are committed rather than fetched at build time.
 */

import { readFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))

export const id = 'wikidata-terms'
export const source = 'wikidata'

/** Which set fills which corpus path. */
const PATHS = {
  direction_cardinal: 'location.direction.cardinal',
  direction_ordinal: 'location.direction.ordinal',
  western_zodiac_sign: 'person.western_zodiac_sign',
  sex: 'person.sex',
}

/**
 * Wikidata labels are per language; Decoy locales are per language *and* region.
 *
 * `pt_BR` and `pt_PT` both take the Portuguese labels, and `en_AU_ocker` takes the English
 * ones. That is right for these sets -- the intercardinals are not regional -- and would be
 * wrong for something like currency or subdivision names, which is why it is a decision
 * made here rather than a helper shared with adapters that must not do it.
 */
function languageOf(code) {
  return code.split('_')[0]
}

export async function run({ locales }) {
  const raw = await readFile(join(here, '..', 'data', 'wikidata-terms.json'), 'utf8')
  const { terms, retrieved } = JSON.parse(raw)

  const contributions = {}
  const stats = {}

  for (const [set, path] of Object.entries(PATHS)) {
    const byLanguage = terms[set]
    if (!byLanguage) throw new Error(`wikidata-terms: no '${set}' in the committed data`)

    let count = 0
    for (const code of locales) {
      if (code === 'base') continue
      // English keeps what `authored.mjs` supplies, so the abbreviations and the words
      // they abbreviate stay in one place and cannot drift apart.
      if (languageOf(code) === 'en') continue
      const values = byLanguage[languageOf(code)]
      if (!Array.isArray(values) || values.length === 0) continue
      ;(contributions[code] ??= {})[path] = values
      count += 1
    }
    stats[set] = count
  }

  if (Object.keys(contributions).length === 0) {
    throw new Error('wikidata-terms produced nothing — is data/wikidata-terms.json present?')
  }

  return { contributions, stats: { retrieved, ...stats } }
}
