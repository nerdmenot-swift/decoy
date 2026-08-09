/**
 * Colour names per language, from Wikidata.
 *
 * Fills:
 *   <each>  color.human
 *
 * English is not here and should not be: `authored.mjs` supplies it from the CSS Color
 * Module's named set, which is a standard with a citation. This covers the locales that
 * had colour names only because faker carried translations of them.
 *
 * ## Why the vocabularies differ per language rather than matching English
 *
 * Translating the CSS names into thirty-odd languages is the obvious move and the wrong
 * one. `papayawhip` and `gainsboro` are not concepts other languages have words for, and a
 * German fixture reading "Papayacreme" would be a translation artefact rather than a colour
 * anybody names. `color.human()` promises a word a person would use, so the right unit is
 * each language's own colour vocabulary.
 *
 * A consequence worth stating: the sets are not parallel. German has words English lacks
 * and the reverse, and no row in one locale corresponds to a row in another. Nothing in
 * Decoy needs them to correspond, and pretending they did would be the translation
 * artefact again by another route.
 *
 * ## Capitalisation is left alone, deliberately
 *
 * The lists are mixed -- French holds `Asperge` beside `abricot` -- and normalising them
 * looks like an easy tidy. It is not. German capitalises its nouns, so lower-casing would
 * make `Anthrazit` wrong; and `Maya-blauw` and `Falurood` take their capitals from a
 * proper noun rather than from a convention, in a language that otherwise does not
 * capitalise. A rule that fixed the untidiness would make individual entries incorrect,
 * and each entry here is the name as its language writes it.
 *
 * **CC0**, so there is nothing to reconcile with Apache-2.0 and no attribution obligation.
 * See `sources/wikidata.json` for why the query results are committed rather than fetched
 * at build time, and `fetch-wikidata-colours.mjs` for the query itself.
 */

import { readFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))

export const id = 'wikidata-colours'
export const source = 'wikidata'

export async function run({ locales }) {
  const raw = await readFile(join(here, '..', 'data', 'wikidata-colours.json'), 'utf8')
  const { colours, retrieved } = JSON.parse(raw)

  const contributions = {}
  const taken = []

  for (const [code, list] of Object.entries(colours)) {
    if (!locales.includes(code)) continue
    // English keeps the CSS named set. A Wikidata list would be a lateral move at best,
    // and it would cost the one colour source in the corpus that cites a standard.
    if (code === 'en') continue
    if (!Array.isArray(list) || list.length === 0) continue
    contributions[code] = { 'color.human': [...list].sort() }
    taken.push(`${code}(${list.length})`)
  }

  if (taken.length === 0) {
    throw new Error('wikidata-colours produced nothing — is data/wikidata-colours.json present?')
  }

  return { contributions, stats: { retrieved, locales: taken.length, taken } }
}
