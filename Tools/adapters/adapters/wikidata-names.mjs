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
}

export async function run({ locales }) {
  const raw = await readFile(join(here, '..', 'data', 'wikidata-names.json'), 'utf8')
  const { names, retrieved } = JSON.parse(raw)

  const contributions = {}
  const taken = []
  const tooThin = []

  for (const [code, sets] of Object.entries(names)) {
    if (!locales.includes(code)) continue

    const contribution = {}
    const deferred = DEFERRED[code] ?? []
    for (const [kind, path] of Object.entries(PATHS)) {
      if (deferred.includes(kind)) continue
      const list = sets[kind]
      if (!Array.isArray(list)) continue
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
