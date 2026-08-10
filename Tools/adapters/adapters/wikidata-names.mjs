/**
 * Given names and surnames per language, from Wikidata.
 *
 * Fills:
 *   <each>  person.first_name.female
 *   <each>  person.first_name.male
 *   <each>  person.last_name.generic
 *
 * The answer to the question the campaign kept running into: there is no consolidated,
 * permissively licensed, pinnable dataset of names by language — except that Wikidata is
 * one, if you ask it rather than download it.
 *
 * **CC0**, so there is nothing to reconcile with Apache-2.0 and no attribution obligation
 * at all. Decoy names it in NOTICE regardless, because being able to say where a value
 * came from is the point of the provenance machinery whether or not anybody requires it.
 *
 * ## Why the data is committed rather than fetched
 *
 * Every other source is a file at a URL with an integrity hash, and the hash is what makes
 * a silently changed upstream fail the build instead of quietly altering everyone's
 * fixtures. A SPARQL endpoint cannot be pinned that way: it answers with whatever Wikidata
 * says today, it is rate-limited, and it returned a truncated body mid-run while this was
 * being written.
 *
 * So `fetch-wikidata-names.mjs` is run by hand and its output is committed. The queries
 * are in that file, so the result can be re-run and diffed — which is a stronger guarantee
 * than a hash over somebody else's server, because it can be checked by inspection.
 *
 * ## What this is not
 *
 * **Not weighted.** The US Census and INSEE lists carry how many people bear each name,
 * which is why `en` and `fr` produce realistic collision rates and these locales do not.
 * Wikidata records that a name exists, not how common it is. A national registry replacing
 * one of these lists is a straight upgrade and should be taken whenever one turns up.
 *
 * **Not a census.** Wikidata's coverage follows editor interest, so a language with an
 * active community has thousands of names and a smaller one has dozens. The floor below
 * is where "a sample of the language" stops being true enough to ship.
 */

import { readFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))

export const id = 'wikidata-names'
export const source = 'wikidata'

/**
 * Below this, a locale keeps whatever it had.
 *
 * Forty names is enough to look like a language and not enough to stop looking like a
 * list — a fixture set of two hundred rows would repeat every name five times. Where
 * Wikidata is this thin, faker's list is usually larger and the trade is not worth making.
 */
const MINIMUM_NAMES = 60

const PATHS = {
  female: 'person.first_name.female',
  male: 'person.first_name.male',
  surname: 'person.last_name.generic',
}

/**
 * Paths a national registry already fills, which this source yields to.
 *
 * Wikidata records that a name exists; a registry records how many people bear it, and that
 * difference is the whole of realistic collision rates. So where both have an answer, the
 * registry wins — this is not a tie to break on coverage.
 *
 * Per-path rather than per-locale, because the registries are not symmetrical. INSEE
 * publishes given names and not surnames, so French surnames are Wikidata's to fill and
 * French given names are not. Getting this wrong is not subtle: the build fails on a
 * collision rather than silently picking one, which is why this list can be trusted to be
 * current.
 */
const DEFERRED = {
  en: ['female', 'male', 'surname'], // Gender-by-Name, then US Census for the surnames.
  fr: ['female', 'male'], // INSEE. Surnames are published commercially only, so not here.
  pl: ['female', 'male'], // PESEL. Surnames are not published; the register covers given names.
  es: ['female', 'male'], // INE. Spanish surnames are published only as a separate paid series.
  fi: ['female', 'male'], // DVV. Finland publishes given names only.
  sv: ['female', 'male', 'surname'], // SCB, the one register that publishes family names too.
  en_GB: ['female', 'male'], // ONS baby names; surnames still come through `en`.
}

/**
 * Wikidata labels are per language; several Decoy locales carry a region and no bare
 * language beside it.
 *
 * Without this the match is by exact code, and eight languages' worth of names were
 * fetched, committed and then silently used by nobody: Portuguese has no `pt` locale, only
 * `pt_BR` and `pt_PT`, so 1,571 Portuguese names sat in the data file while Portuguese
 * fixtures were served English ones. The same for Czech, Slovene, Norwegian, Bengali,
 * Georgian, Serbian and Yoruba -- about 10,700 names in total, present and unreachable.
 *
 * An exact match still wins where there is one. This only fills in for a locale whose
 * language has data that nothing else claims.
 */
function languageOf(code) {
  return code.split('_')[0]
}

/**
 * Some locales name their script, and the label store does not separate them.
 *
 * Serbian is written in both alphabets and Wikidata holds both under `sr`: the female list
 * runs `Jasenka, Јарослава, Јелена`. Decoy's locale is `sr_RS_latin`, so taking the
 * language wholesale would put Cyrillic names in a Latin-script fixture -- which reads as
 * data corruption rather than as a language.
 *
 * Only applied where the locale declares a script. Georgian and Bengali have one alphabet
 * each and need no filtering; `ka_GE` and `bn_BD` take everything their language offers.
 */
const SCRIPTS = {
  latin: /^[\p{Script=Latin}\p{Mark}\p{Punctuation}\s]+$/u,
  cyrl: /^[\p{Script=Cyrillic}\p{Mark}\p{Punctuation}\s]+$/u,
}

function scriptOf(code) {
  const last = code.split('_').at(-1)
  return SCRIPTS[last] ?? null
}

/**
 * Whether an ancestor in this locale's chain already receives the same language's names.
 *
 * `de_AT` resolves through `de`, which has German names, so writing them into `de_AT` as
 * well would put a second copy of 5,377 names in the corpus to say what the chain already
 * says. The first version of the language fallback did exactly that and grew nine locales
 * by a full duplicate each.
 *
 * The bare-language lookup is what needs guarding, not the exact-code one: an exact match
 * means the register really does hold something specific to that locale.
 */
function ancestorCovers(code, chain, names) {
  const language = languageOf(code)
  for (const ancestor of (chain ?? []).slice(1)) {
    if (languageOf(ancestor) !== language) continue
    if (names[ancestor] ?? names[languageOf(ancestor)]) return true
  }
  return false
}

export async function run({ locales, chains }) {
  const raw = await readFile(join(here, '..', 'data', 'wikidata-names.json'), 'utf8')
  const { names, retrieved } = JSON.parse(raw)

  const contributions = {}
  const taken = []
  const tooThin = []

  // Driven by the locale roster rather than by the data file. The other way round matches
  // on exact code and silently skips every locale whose language has no bare entry, which
  // is what left Portuguese, Czech, Slovene, Norwegian, Bengali, Georgian, Serbian and
  // Yoruba fixtures on English names while their names sat in the file.
  for (const code of locales) {
    if (code === 'base') continue
    const exact = names[code]
    if (!exact && ancestorCovers(code, chains?.[code], names)) continue
    const sets = exact ?? names[languageOf(code)]
    if (!sets) continue

    const script = scriptOf(code)
    const contribution = {}
    const deferred = DEFERRED[code] ?? DEFERRED[languageOf(code)] ?? []
    for (const [kind, path] of Object.entries(PATHS)) {
      if (deferred.includes(kind)) continue
      let list = sets[kind]
      if (!Array.isArray(list)) continue
      if (script) list = list.filter((value) => script.test(value))
      if (list.length < MINIMUM_NAMES) {
        tooThin.push(`${code}.${kind}(${list.length})`)
        continue
      }
      contribution[path] = [...list].sort()
    }

    if (Object.keys(contribution).length > 0) {
      contributions[code] = contribution
      taken.push(`${code}(${Object.values(contribution).reduce((n, l) => n + l.length, 0)})`)
    }
  }

  if (taken.length === 0) {
    throw new Error('wikidata-names produced nothing — is data/wikidata-names.json present?')
  }

  return {
    contributions,
    stats: { retrieved, locales: taken.length, taken, tooThin },
  }
}
