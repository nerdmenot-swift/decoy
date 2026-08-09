/**
 * Fetches given names and surnames per language from Wikidata, and writes them to
 * `data/wikidata-names.json`.
 *
 * Run by hand, not by the build:
 *
 *     node Tools/adapters/fetch-wikidata-names.mjs
 *
 * ## Why the result is committed rather than queried at build time
 *
 * Every other source here is a file at a URL with an integrity hash, and the hash is the
 * point: a silently changed upstream fails the build instead of quietly altering
 * everyone's fixtures. A SPARQL endpoint cannot be pinned that way. It returns whatever
 * Wikidata says today, it is rate-limited, and it answered one of these very queries with
 * a 502 while this file was being written.
 *
 * So the query runs once, deliberately, and its output is committed. The queries are
 * below, so anyone can re-run them and diff the result — which is a stronger guarantee
 * than a hash over somebody else's server, because it can be checked by inspection rather
 * than only by comparison.
 *
 * ## Why Wikidata rather than scraping
 *
 * Wikidata is CC0: no attribution required, no share-alike, nothing to reconcile with
 * Apache-2.0. It is also a database with a query interface rather than pages to scrape,
 * which matters beyond politeness — scraped content carries whatever licence the page had,
 * usually all-rights-reserved or CC BY-SA, and a corpus that cannot say where a value came
 * from is the thing this project exists to replace.
 */

import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))

const ENDPOINT = 'https://query.wikidata.org/sparql'
const AGENT = 'DecoyCorpusBuild/1.0 (https://github.com/NerdMeNot/decoy)'

/** Wikidata classes for the three things wanted. */
const CLASSES = {
  female: 'Q11879590',
  male: 'Q12308941',
  surname: 'Q101352',
}

/**
 * Locale to the Wikidata item for its language.
 *
 * `P407` — "language of work or name" — is what ties a name to a language, and it is the
 * property that makes this usable at all: without it a query returns every name that
 * happens to have a German *label*, which is every name in the world.
 */
const LANGUAGES = {
  de: 'Q188', es: 'Q1321', it: 'Q652', pt: 'Q5146', nl: 'Q7411', pl: 'Q809',
  sv: 'Q9027', da: 'Q9035', nb: 'Q9043', fi: 'Q1412', cs: 'Q9056', sk: 'Q9058',
  tr: 'Q256', ru: 'Q7737', uk: 'Q8798', el: 'Q9129', hu: 'Q9067', ro: 'Q7913',
  hr: 'Q6654', sl: 'Q9063', lv: 'Q9078', lt: 'Q9083', et: 'Q9072', id: 'Q9240',
  vi: 'Q9199', th: 'Q9217', fa: 'Q9168', he: 'Q9288', ar: 'Q13955', ja: 'Q5287',
  ko: 'Q9176', zh: 'Q7850', hi: 'Q1568', fr: 'Q150', en: 'Q1860',
  // The eighteen the roster needs beyond the obvious ones. Every QID here was checked
  // against Wikidata's own label rather than typed from memory: a wrong one returns
  // nothing, which reads as "Wikidata has no Zulu names" instead of "that is not Zulu".
  af: 'Q14196', az: 'Q9292', bn: 'Q9610', cy: 'Q9309', dv: 'Q32656', eo: 'Q143',
  hy: 'Q8785', ka: 'Q8108', ku: 'Q36368', mk: 'Q9296', mn: 'Q9246', ne: 'Q33823',
  sr: 'Q9299', ta: 'Q5885', ur: 'Q1617', uz: 'Q9264', yo: 'Q34311', zu: 'Q10179',
}

/**
 * The triple order matters and is not stylistic.
 *
 * Putting `wdt:P407` first narrows to one language before touching the label index;
 * putting `wdt:P31` first makes the engine consider every family name in Wikidata — about
 * a million of them — and the query times out. That is the difference between this
 * working and not.
 */
function queryFor(classID, languageID, code) {
  return `SELECT DISTINCT ?l WHERE {
  ?i wdt:P407 wd:${languageID} ;
     wdt:P31 wd:${classID} ;
     rdfs:label ?l .
  FILTER(LANG(?l) = "${code}")
} LIMIT 4000`
}

async function ask(query) {
  const url = `${ENDPOINT}?query=${encodeURIComponent(query)}`
  for (let attempt = 0; attempt < 4; attempt++) {
    try {
      const response = await fetch(url, {
        headers: { Accept: 'application/sparql-results+json', 'User-Agent': AGENT },
      })
      if (response.ok) {
        // Parsed inside the retry, not after it. A 200 with a truncated body is a real
        // failure mode of this endpoint under load — it cut off mid-string on the
        // eleventh language and took the whole run with it, because the parse sat outside
        // the loop where nothing could retry it.
        const body = await response.json()
        return body.results.bindings.map((row) => row.l.value)
      }
    } catch {
      // Truncated body, reset connection, or malformed JSON. All retryable.
    }
    // Shared infrastructure that answers 429 and 502 under load. Backing off is the
    // courtesy that keeps it usable, and this script is run by hand anyway.
    await new Promise((resolve) => setTimeout(resolve, 4000 * (attempt + 1)))
  }
  return null
}

/**
 * A label is a name only if it looks like one.
 *
 * Wikidata labels carry disambiguators and transliterations — `Müller (Familienname)`,
 * `John Smith`, `名前` glossed in Latin. Anything with a bracket, a digit or a space is
 * dropped, which loses a few genuine compound surnames and keeps the list clean.
 */
function usable(label) {
  if (label.length < 2 || label.length > 24) return false
  if (/[()[\]{}0-9.,;:!?/\\]/.test(label)) return false
  if (/\s/.test(label)) return false
  return true
}

const RETRIEVED = new Date().toISOString().slice(0, 10)

// Resume rather than restart. Fifty languages at three queries each is a long, polite
// crawl over shared infrastructure, and re-asking for what is already on disk wastes
// somebody else's rate limit as well as this session's time. Delete the file to force a
// full refresh.
const out = await readFile(join(here, 'data', 'wikidata-names.json'), 'utf8')
  .then((text) => JSON.parse(text).names)
  .catch(() => ({}))
if (Object.keys(out).length > 0) {
  process.stderr.write(`resuming; ${Object.keys(out).length} locales already fetched\n`)
}
for (const [code, languageID] of Object.entries(LANGUAGES)) {
  if (out[code]) continue
  const forLocale = {}
  for (const [kind, classID] of Object.entries(CLASSES)) {
    const labels = await ask(queryFor(classID, languageID, code))
    if (labels === null) {
      process.stderr.write(`${code} ${kind}: endpoint gave up\n`)
      continue
    }
    const kept = [...new Set(labels.filter(usable))].sort()
    if (kept.length >= 40) forLocale[kind] = kept
    process.stderr.write(`${code} ${kind}: ${kept.length} of ${labels.length}\n`)
    await new Promise((resolve) => setTimeout(resolve, 1200))
  }
  if (Object.keys(forLocale).length > 0) out[code] = forLocale

  // Written after every locale rather than once at the end. Thirty-four languages at
  // three queries each is twenty minutes of somebody else's rate limit, and losing all
  // of it to a failure on the last one is the kind of thing that only happens once
  // before you fix it.
  await mkdir(join(here, 'data'), { recursive: true })
  await writeFile(
    join(here, 'data', 'wikidata-names.json'),
    JSON.stringify({ retrieved: RETRIEVED, names: out }, null, 1),
  )
}

process.stderr.write(`\nwrote ${Object.keys(out).length} locales\n`)
