/**
 * Fetches small fixed concept sets per language from Wikidata, and writes them to
 * `data/wikidata-terms.json`.
 *
 * Run by hand, not by the build:
 *
 *     node Tools/adapters/fetch-wikidata-terms.mjs
 *
 * The third of the Wikidata fetchers, and shaped differently from the other two on
 * purpose. Names and colours are open-ended catalogues, so those ask one question per
 * language and take whatever comes back. The sets here are closed and known -- there are
 * four intercardinal directions and twelve occidental zodiac signs, and there will not be
 * a thirteenth -- so each is one query across every language at once, which is both faster
 * and kinder to a shared endpoint.
 *
 * ## Every identifier here was looked up, not recalled
 *
 * This matters more than it sounds. The first attempt at the intercardinals guessed
 * `Q1704632` for northeast; it is a man called Josef Gabriel, and `Q1704634` is a wolf
 * spider. A wrong identifier does not fail loudly -- it returns a plausible label in the
 * right language and quietly puts a spider in the compass.
 *
 * The zodiac set was found the same way, by asking Wikidata what class its own "Aries"
 * belongs to rather than assuming: the answer is `Q1795024`, "occidental astrological
 * sign", and the obvious-looking constellation items are a different thing that happens to
 * share most of its names.
 */

import { mkdir, writeFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))

const ENDPOINT = 'https://query.wikidata.org/sparql'
const AGENT = 'DecoyCorpusBuild/1.0 (https://github.com/NerdMeNot/decoy)'

/**
 * The concept sets, each either an explicit member list or a class to enumerate.
 *
 * The cardinals came from CLDR's `coordinateUnit` first, on the grounds that it gives the
 * compass form -- German `Nord` rather than `Norden`. Checking more than two locales
 * killed that: `coordinateUnit` labels a *latitude or longitude*, not a compass bearing,
 * and locales render it as they see fit. Japanese returns 北緯, "north latitude". Welsh
 * returns `i'r gogledd`, "to the north". Hungarian returns the abbreviations. Wikidata's
 * plain items are right in all fourteen languages spot-checked, so they are what is used.
 *
 * The cost is that German gets the noun `Norden` where the compass form is `Nord`. That is
 * a real if small imprecision, taken knowingly: `Norden` is correct German for north, and
 * the alternative was a source that is correct for German and wrong for Japanese.
 */
const SETS = {
  direction_cardinal: {
    members: { north: 'Q659', east: 'Q684', south: 'Q667', west: 'Q679' },
  },
  direction_ordinal: {
    members: {
      northeast: 'Q6497686',
      northwest: 'Q5491373',
      southeast: 'Q6452640',
      southwest: 'Q2381698',
    },
  },
  /**
   * The twelve, named explicitly and in their conventional order.
   *
   * Enumerating the class was the first approach and it returned thirteen: Ophiuchus is a
   * real instance of "occidental astrological sign", described by Wikidata as the "ninth
   * or thirteenth", and belongs to the thirteen-sign zodiac rather than to the twelve that
   * `western_zodiac_sign` means. Excluding it by name is honest; loosening the count check
   * that caught it would not be, and the class can gain another member tomorrow.
   */
  western_zodiac_sign: {
    members: {
      aries: 'Q32067', taurus: 'Q164016', gemini: 'Q129214', cancer: 'Q161701',
      leo: 'Q159816', virgo: 'Q134061', libra: 'Q134394', scorpio: 'Q134398',
      sagittarius: 'Q2194186', capricorn: 'Q164272', aquarius: 'Q162119',
      pisces: 'Q1254190',
    },
  },
  sex: { members: { male: 'Q6581097', female: 'Q6581072' } },
}

async function ask(query) {
  for (let attempt = 0; attempt < 5; attempt++) {
    try {
      const response = await fetch(`${ENDPOINT}?query=${encodeURIComponent(query)}`, {
        headers: { Accept: 'application/sparql-results+json', 'User-Agent': AGENT },
      })
      if (response.ok) {
        const body = await response.json()
        return body.results.bindings
      }
    } catch {
      // Truncated body, reset connection, or malformed JSON. All retryable.
    }
    await new Promise((resolve) => setTimeout(resolve, 5000 * (attempt + 1)))
  }
  return null
}

/**
 * Every member in the language, or nothing.
 *
 * The untranslated-label check that `fetch-wikidata-colours.mjs` needs would be actively
 * wrong here: Spanish for Aries is `Aries`, and dropping a label for matching English
 * would delete a correct translation from half the zodiac.
 *
 * A closed set admits a better check anyway. If a language has labels for all twelve signs
 * it has been translated; if it has nine, somebody is part-way through and the gaps would
 * ship as a set that silently lacks Capricorn. So it is all or nothing, which is exact and
 * needs no guessing about what a word looks like.
 */
function completeSetsOnly(rows, order, expected) {
  const byLanguage = {}
  for (const row of rows) {
    const key = row.i.value.split('/').pop()
    ;(byLanguage[row.l['xml:lang']] ??= {})[key] = row.l.value
  }
  const out = {}
  for (const [language, found] of Object.entries(byLanguage)) {
    const values = order.map((qid) => found[qid])
    if (values.length !== expected || values.some((v) => v === undefined)) continue
    // Deduplicated because a language can give two members the same word, and a set that
    // reads ["north-east", "north-east", ...] is worse than one that is simply absent.
    if (new Set(values).size !== values.length) continue
    out[language] = values
  }
  return out
}

const RETRIEVED = new Date().toISOString().slice(0, 10)
const out = {}

for (const [name, spec] of Object.entries(SETS)) {
  let order
  let rows

  if (spec.members) {
    order = Object.values(spec.members)
    rows = await ask(`SELECT ?i ?l WHERE {
  VALUES ?i { ${order.map((q) => `wd:${q}`).join(' ')} }
  ?i rdfs:label ?l .
}`)
  } else {
    const members = await ask(
      `SELECT ?i WHERE { ?i wdt:P31 wd:${spec.instancesOf} } LIMIT 100`,
    )
    if (members === null) {
      process.stderr.write(`${name}: endpoint gave up enumerating the class\n`)
      continue
    }
    order = members.map((row) => row.i.value.split('/').pop())
    if (spec.expect && order.length !== spec.expect) {
      // A closed set that changed size means the class is not what it was taken to be,
      // and shipping it anyway is how a wolf spider gets into the compass.
      throw new Error(
        `${name}: expected ${spec.expect} members of ${spec.instancesOf}, found ${order.length}`,
      )
    }
    rows = await ask(`SELECT ?i ?l WHERE {
  VALUES ?i { ${order.map((q) => `wd:${q}`).join(' ')} }
  ?i rdfs:label ?l .
}`)
  }

  if (rows === null) {
    process.stderr.write(`${name}: endpoint gave up\n`)
    continue
  }
  out[name] = completeSetsOnly(rows, order, order.length)
  process.stderr.write(
    `${name}: ${order.length} members, complete in ${Object.keys(out[name]).length} languages\n`,
  )
  await new Promise((resolve) => setTimeout(resolve, 1500))
}

await mkdir(join(here, 'data'), { recursive: true })
await writeFile(
  join(here, 'data', 'wikidata-terms.json'),
  JSON.stringify({ retrieved: RETRIEVED, terms: out }, null, 1),
)
process.stderr.write(`\nwrote ${Object.keys(out).length} sets\n`)
