/**
 * Word lists by part of speech, from the Open Multilingual Wordnet.
 *
 * Fills:
 *   <each>  word.noun, word.verb, word.adjective, word.adverb
 *
 * Only permissively licensed OMW members are used, and each is pinned as its own source
 * so the corpus records the licence that actually covers each language. They range from
 * Apache-2.0 (Greek) through MIT (Indonesian) and CC BY 3.0 (Spanish, Finnish, Croatian,
 * Italian, Swedish) to the Princeton WordNet licence (English, Japanese, Thai, Hebrew,
 * Polish, Danish, Norwegian, Chinese).
 *
 * German (OdeNet), French (WOLF), Dutch, Portuguese, Romanian, Slovak, Slovenian,
 * Lithuanian and Arabic are deliberately absent: all are CC BY-SA or CeCILL, and
 * share-alike does not compose with Apache-2.0. Those locales fall through to English
 * rather than shipping data Decoy cannot license — which is a real loss for German,
 * French and Portuguese, all of which had faker word lists before.
 */

import { readFile } from 'node:fs/promises'
import { join } from 'node:path'

export const id = 'wordnet'

/** Every wordnet, the locales it serves, and the artifact carrying it. */
const WORDNETS = [
  { source: 'omw-cmn', locales: ['zh_CN'] },
  { source: 'omw-da', locales: ['da'] },
  { source: 'omw-el', locales: ['el'] },
  { source: 'omw-en', locales: ['en'] },
  { source: 'omw-es', locales: ['es'] },
  { source: 'omw-fi', locales: ['fi'] },
  { source: 'omw-he', locales: ['he'] },
  { source: 'omw-hr', locales: ['hr'] },
  { source: 'omw-id', locales: ['id_ID'] },
  { source: 'omw-it', locales: ['it'] },
  { source: 'omw-ja', locales: ['ja'] },
  { source: 'omw-nb', locales: ['nb_NO'] },
  { source: 'omw-pl', locales: ['pl'] },
  { source: 'omw-sv', locales: ['sv'] },
  { source: 'omw-th', locales: ['th'] },
]

export const sources = WORDNETS.map((w) => w.source)

/** WordNet's part-of-speech codes. `s` is a satellite adjective, still an adjective. */
const PATH_FOR_POS = {
  n: 'word.noun',
  v: 'word.verb',
  a: 'word.adjective',
  s: 'word.adjective',
  r: 'word.adverb',
}

/**
 * Words carrying at least this many senses.
 *
 * WordNet has no frequency data, but polysemy is a serviceable proxy for it: common
 * words accumulate senses and obscure ones do not. English drops from 68,923 words to
 * 21,431 under this rule, which is still twenty times what the bootstrap corpus had —
 * and the tail it removes is the technical vocabulary nobody wants in a fixture.
 */
const MINIMUM_SENSES = 2

/** Below this a filtered list is too thin to be worth the filter, so keep everything. */
const VIABLE_LIST = 40

/**
 * Whether a lemma is a single ordinary word.
 *
 * OMW lemmas include multi-word expressions (`abnormal_condition`) and proper nouns.
 * The lower length bound is script-aware: three characters is reasonable for Latin
 * script and would discard most of Japanese, Chinese and Thai, where words are short.
 */
function isOrdinaryWord(word) {
  if (/[ _\-0-9.'’]/.test(word)) return false
  // Proper nouns in cased scripts. For uncased scripts this is identity and passes.
  if (word !== word.toLowerCase()) return false
  const isLatin = /^[a-z]+$/.test(word)
  return isLatin ? word.length >= 3 && word.length <= 14 : word.length >= 1 && word.length <= 12
}

/** Extracts lemmas per part of speech, with their sense counts. */
function parseLexicon(xml) {
  const byPos = {}
  for (const entry of xml.split('<LexicalEntry').slice(1)) {
    const lemma = entry.match(/<Lemma\s+writtenForm="([^"]*)"\s+partOfSpeech="([^"]*)"/)
    if (!lemma) continue

    const [, rawWord, pos] = lemma
    const path = PATH_FOR_POS[pos]
    if (!path) continue

    // XML entities appear in writtenForm; only these five are legal there.
    const word = rawWord
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")

    if (!isOrdinaryWord(word)) continue

    const senses = (entry.match(/<Sense /g) ?? []).length
    ;(byPos[path] ??= new Map()).set(word, Math.max(byPos[path].get(word) ?? 0, senses))
  }
  return byPos
}

export async function run({ artifacts }) {
  const contributions = {}
  const sourceByLocale = {}
  const stats = {}

  for (const { source, locales } of WORDNETS) {
    const code = source.replace('omw-', '')
    const directory = artifacts[`wn_${code}`]
    if (!directory) throw new Error(`${source}: artifact wn_${code} was not loaded`)

    const xml = await readFile(join(directory, source, `${source}.xml`), 'utf8')
    const byPos = parseLexicon(xml)

    const paths = {}
    for (const [path, words] of Object.entries(byPos)) {
      const common = [...words.entries()]
        .filter(([, senses]) => senses >= MINIMUM_SENSES)
        .map(([word]) => word)
      // Smaller wordnets have too few polysemous entries for the filter to leave a
      // usable list; there, everything is better than almost nothing.
      const chosen = common.length >= VIABLE_LIST ? common : [...words.keys()]
      if (chosen.length > 0) paths[path] = chosen.sort()
    }

    if (Object.keys(paths).length === 0) continue

    for (const locale of locales) {
      contributions[locale] = paths
      sourceByLocale[locale] = source
    }
    stats[code] = Object.values(paths).reduce((sum, list) => sum + list.length, 0)
  }

  return { contributions, sourceByLocale, stats }
}
