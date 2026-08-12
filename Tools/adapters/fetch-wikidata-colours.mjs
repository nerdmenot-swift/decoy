/**
 * Fetches colour names per language from Wikidata, and writes them to
 * `data/wikidata-colours.json`.
 *
 * Run by hand, not by the build:
 *
 *     node Tools/adapters/fetch-wikidata-colours.mjs
 *
 * The same arrangement as `fetch-wikidata-names.mjs` and for the same reason: a SPARQL
 * endpoint cannot carry an integrity hash, so the query runs once, deliberately, and its
 * output is committed beside the query that produced it.
 *
 * ## Why per-language vocabularies rather than one translated set
 *
 * English colours come from the CSS Color Module's named set, which is a standard and can
 * be cited. The obvious move is to translate those forty-five into every other language,
 * and it is the wrong one: `papayawhip` and `gainsboro` are not concepts other languages
 * have words for, and a German fixture reading "Papayacreme" would be a translation
 * artefact rather than a colour anybody names.
 *
 * `color.human()` promises a colour word a person would actually use. That makes the right
 * unit a language's own colour vocabulary, which is what this asks for -- German gets
 * `Blau` and `Anthrazit`, Japanese gets `茶色` and `蜜柑色`.
 */

import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))

const ENDPOINT = 'https://query.wikidata.org/sparql'
const AGENT = 'DecoyCorpusBuild/1.0 (https://github.com/nerdmenot-swift/decoy)'

/** Wikidata's item for the concept "colour". Everything wanted is an instance of it. */
const COLOUR = 'Q1075'

/**
 * Locale to the Wikidata item for its language.
 *
 * The set is the locales that carried colour names before this existed, so the change is a
 * replacement rather than an expansion -- a locale that had none still has none, and its
 * chain resolves to English exactly as it did.
 *
 * Several are locale codes rather than bare languages (`pt_BR`, `zh_TW`, `es_MX`). They map
 * to the same language item as their parent, because Wikidata labels are per language and
 * not per region; the regional split lives in Decoy's chain, not here.
 */
const LANGUAGES = {
  ar: 'Q13955', az: 'Q9292', cy: 'Q9309', de: 'Q188', el: 'Q9129', eo: 'Q143',
  es: 'Q1321', es_MX: 'Q1321', fa: 'Q9168', fr: 'Q150', he: 'Q9288', hu: 'Q9067',
  hy: 'Q8785', id_ID: 'Q9240', ja: 'Q5287', ko: 'Q9176', lv: 'Q9078', nb_NO: 'Q9043',
  nl: 'Q7411', pl: 'Q809', pt_BR: 'Q5146', pt_PT: 'Q5146', ru: 'Q7737', sv: 'Q9027',
  th: 'Q9217', tr: 'Q256', ur: 'Q1617', zh_CN: 'Q7850', zh_TW: 'Q7850',
  dv: 'Q32656', ku_kmr_latin: 'Q36368', mn_MN_cyrl: 'Q9246', uz_UZ_latin: 'Q9264',
}

/** The language subtag Wikidata labels are tagged with, which is not the locale code. */
function subtagFor(code) {
  return code.split('_')[0]
}

/**
 * The English label comes back alongside the target one, and it is what makes this usable.
 *
 * A Wikidata label tagged `fr` is not necessarily French. Where nobody has translated an
 * item, contributors routinely paste the English string in and tag it anyway, so the first
 * run put `Fallow`, `Flax` and `Alvon` in the French colour list. A fixture library that
 * puts English words in French rows is worse than one that has no French colours.
 *
 * Comparing the two labels catches exactly that: same string in both languages means
 * nobody translated it. The cost is the internationalisms -- `Beige` really is the German
 * word for beige and goes out with the rest -- which is worth paying, because the check is
 * exact and the alternative is guessing from the alphabet.
 */
function queryFor(languageTag) {
  return `SELECT DISTINCT ?l ?en WHERE {
  ?i wdt:P31 wd:${COLOUR} ;
     rdfs:label ?l .
  FILTER(LANG(?l) = "${languageTag}")
  OPTIONAL { ?i rdfs:label ?en FILTER(LANG(?en) = "en") }
} LIMIT 1000`
}

async function ask(query) {
  for (let attempt = 0; attempt < 5; attempt++) {
    try {
      const response = await fetch(`${ENDPOINT}?query=${encodeURIComponent(query)}`, {
        headers: { Accept: 'application/sparql-results+json', 'User-Agent': AGENT },
      })
      if (response.ok) {
        // Parsed inside the retry rather than after it: a 200 with a truncated body is a
        // real failure mode of this endpoint under load.
        const body = await response.json()
        return body.results.bindings.map((row) => ({
          label: row.l.value,
          english: row.en?.value ?? null,
        }))
      }
      // 429 arrived on the third language while this was being written. Backing off is
      // the courtesy that keeps a shared endpoint usable.
    } catch {
      // Truncated body, reset connection, or malformed JSON. All retryable.
    }
    await new Promise((resolve) => setTimeout(resolve, 5000 * (attempt + 1)))
  }
  return null
}

/**
 * A label is a colour word only if somebody would say it.
 *
 * Wikidata's colour items run from `Blau` to `Kassler Erde` to `コズミックラテ` -- pigment
 * trade names and one colour named after the average light of the universe. Dropping
 * anything with a space, a digit or a bracket keeps the everyday vocabulary and loses the
 * catalogue entries, which is the right side of that trade for a fixture library.
 */
function usable(label) {
  if (label.length < 2 || label.length > 24) return false
  if (/[()[\]{}0-9.,;:!?/\\]/.test(label)) return false
  if (/\s/.test(label)) return false
  return true
}

/**
 * Below this a locale keeps what it had.
 *
 * Colour vocabularies are small by nature -- English ships forty-five -- so the floor is
 * lower than the one for names. Twelve is about where a fixture set stops repeating the
 * same three words on every row.
 */
const MINIMUM = 12

const RETRIEVED = new Date().toISOString().slice(0, 10)

const out = await readFile(join(here, 'data', 'wikidata-colours.json'), 'utf8')
  .then((text) => JSON.parse(text).colours)
  .catch(() => ({}))
if (Object.keys(out).length > 0) {
  process.stderr.write(`resuming; ${Object.keys(out).length} locales already fetched\n`)
}

// One request per distinct language, not per locale: `pt_BR` and `pt_PT` ask Wikidata the
// same question, and asking it twice spends somebody else's rate limit on a known answer.
const byTag = {}
for (const [code, languageID] of Object.entries(LANGUAGES)) {
  const tag = subtagFor(code)
  ;(byTag[tag] ??= { languageID, codes: [] }).codes.push(code)
}

for (const [tag, { codes }] of Object.entries(byTag)) {
  if (codes.every((code) => out[code])) continue
  const rows = await ask(queryFor(tag))
  if (rows === null) {
    process.stderr.write(`${tag}: endpoint gave up\n`)
    continue
  }
  // Compared case-insensitively, because the two labels are entered by different people
  // and agree on the word without agreeing on the capital. `Fallow`, `Flax` and `Isabelle`
  // all survived an exact comparison against an English `fallow`, `flax` and `isabelle`,
  // which is the whole failure this check exists to prevent.
  const sameWord = (a, b) => a.trim().toLocaleLowerCase() === b.trim().toLocaleLowerCase()
  const translated =
    tag === 'en'
      ? rows
      : rows.filter((row) => row.english === null || !sameWord(row.english, row.label))
  const untranslated = rows.length - translated.length
  const kept = [...new Set(translated.map((row) => row.label).filter(usable))].sort()
  process.stderr.write(
    `${tag}: ${kept.length} of ${rows.length} (${untranslated} untranslated) -> ${codes.join(', ')}\n`,
  )
  if (kept.length >= MINIMUM) for (const code of codes) out[code] = kept

  await mkdir(join(here, 'data'), { recursive: true })
  await writeFile(
    join(here, 'data', 'wikidata-colours.json'),
    JSON.stringify({ retrieved: RETRIEVED, colours: out }, null, 1),
  )
  await new Promise((resolve) => setTimeout(resolve, 1500))
}

process.stderr.write(`\nwrote ${Object.keys(out).length} locales\n`)
