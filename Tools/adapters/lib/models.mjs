/**
 * Trains a generative model for every name field a locale has enough data for.
 *
 * A pipeline stage rather than an adapter, and that placement is the whole design. An
 * adapter sees only its own contribution; a model has to be trained on what a locale
 * *ends up with*, which is whatever won the merge — the Census surnames in `en`, faker's
 * in `de`, and a future replacement in either without this code changing.
 *
 * Nothing here replaces anything. Each model is written to a parallel path and the list
 * it was trained on stays exactly where it was, because the two answer different
 * questions: the list carries real frequencies and real names, the model carries neither
 * and is the only one of the two that never names a real person.
 */

import { readFile, readdir } from 'node:fs/promises'
import { join } from 'node:path'

import {
  blocklistFilter,
  bloomFilter,
  isViable,
  orderFor,
  train,
  typicalLength,
} from './ngram.mjs'

/**
 * Fields worth generating, and where the model goes.
 *
 * Names only, deliberately. A generated city is a place that does not exist, which breaks
 * anything validating fixtures against a gazetteer, and a generated company name is not
 * anybody's personal data. The argument for generating rather than listing is at its
 * strongest for names and gets weaker with every step away from them.
 */
export const MODELLED_FIELDS = [
  ['person.first_name.female', 'person.first_name_model.female'],
  ['person.first_name.male', 'person.first_name_model.male'],
  ['person.first_name.generic', 'person.first_name_model.generic'],
  ['person.last_name.generic', 'person.last_name_model.generic'],
  ['person.last_name.female', 'person.last_name_model.female'],
  ['person.last_name.male', 'person.last_name_model.male'],
  ['person.middle_name.generic', 'person.middle_name_model.generic'],
]

/** Reads a dotted path out of a nested object. */
function at(node, path) {
  let cursor = node
  for (const part of path.split('.')) {
    if (cursor === null || typeof cursor !== 'object' || !(part in cursor)) return undefined
    cursor = cursor[part]
  }
  return cursor
}

/** Writes a dotted path into a nested object, creating what it needs. */
function put(node, path, value) {
  const parts = path.split('.')
  let cursor = node
  for (const part of parts.slice(0, -1)) {
    if (typeof cursor[part] !== 'object' || cursor[part] === null) cursor[part] = {}
    cursor = cursor[part]
  }
  cursor[parts.at(-1)] = value
}

/**
 * The strings in a field, whether it is a plain list or a weighted one.
 *
 * Weights are read and discarded on purpose: the model is trained on each name once
 * regardless of how many people bear it. Training on the counts would make it produce
 * near-misses of the twenty commonest names rather than the shape of the language.
 */
function valuesOf(field) {
  if (!Array.isArray(field)) return null
  const strings = field.map((item) =>
    typeof item === 'string' ? item : typeof item?.value === 'string' ? item.value : null,
  )
  return strings.every((s) => s !== null) ? strings : null
}

/**
 * Loads the blocklists, keyed by the language code they screen.
 *
 * One file per language upstream, twenty-eight of them, and a locale with no matching
 * file gets no screen. That is stated rather than papered over with the English list:
 * English profanity cannot appear in a model trained on Japanese, so an English screen on
 * `ja` would cost lookups and catch nothing, while implying a protection that is not
 * there. `decoy-validate` reports which locales ship a model without one.
 */
export async function loadBlocklists(artifactDir) {
  const [root] = await readdir(artifactDir)
  const base = join(artifactDir, root)
  const files = (await readdir(base)).filter((name) => /^[a-z]{2,3}(-|$)/.test(name))

  const lists = new Map()
  for (const file of files) {
    const terms = (await readFile(join(base, file), 'utf8')).split('\n').filter(Boolean)
    if (terms.length > 0) lists.set(file, terms)
  }
  if (lists.size < 20) {
    throw new Error(`only ${lists.size} blocklists found — verify before re-pinning`)
  }
  return lists
}

/** The blocklist covering a locale, by language, ignoring the region. */
function screenFor(lists, code) {
  const language = code.split('_')[0].toLowerCase()
  return lists.get(language) ?? null
}

/**
 * Trains every viable model for one locale, mutating `definitions` in place.
 *
 * Returns what was done, so the run can report it rather than the caller guessing.
 */
export function trainLocale(code, definitions, blocklists) {
  const screenTerms = screenFor(blocklists, code)
  const screen = screenTerms ? blocklistFilter(screenTerms) : null
  const trained = []
  const skipped = []

  for (const [from, to] of MODELLED_FIELDS) {
    const values = valuesOf(at(definitions, from))
    if (values === null) continue

    const unique = [...new Set(values)]
    const distinct = unique.length
    if (orderFor(distinct, typicalLength(unique)) === null) {
      // Not a failure. Most locales carry a few dozen names and no order of n-gram turns
      // those into a language model; see MINIMUM_TRAINING_VALUES.
      skipped.push(`${from}(${distinct})`)
      continue
    }

    // Trained on this sub-list, screened against every sibling of it.
    //
    // `person.first_name` splits into `generic`, `female` and `male`, and those lists
    // overlap without being equal. A model trained on the 2,240 generic names and
    // screened only against them will happily emit a name that sits in the 473-name
    // female list — novel for the list it learned from, and a real given name in this
    // locale, which is the thing a caller actually asked not to get. The guarantee has to
    // be "not a real value for this field" rather than "not in this particular sub-list".
    const siblings = Object.entries(at(definitions, from.split('.').slice(0, -1).join('.')) ?? {})
      .flatMap(([, list]) => valuesOf(list) ?? [])
    const guardedAgainst = [...new Set([...unique, ...siblings])]

    const model = train(values)

    // Trained, then made to prove it can generate. A model that only recites is worse
    // than no model: the Bloom filter rejects every candidate, the sampler exhausts its
    // attempts and returns nothing, and the caller gets an empty string from a generator
    // that reported success. Japanese did exactly that before the order became
    // length-aware, and something else will do it again.
    const check = isViable(model, guardedAgainst)
    if (!check.viable) {
      skipped.push(`${from}(${distinct}, ${Math.round(check.novel * 100)}% novel)`)
      continue
    }

    const filter = bloomFilter(guardedAgainst)
    put(definitions, to, {
      __model: {
        ...model,
        filterHashCount: filter.hashCount,
        filterBits: Buffer.from(filter.bits).toString('base64'),
        ...(screen
          ? {
              blockHashCount: screen.hashCount,
              blockMinLength: screen.minLength,
              blockBits: Buffer.from(screen.bits).toString('base64'),
            }
          : {}),
      },
    })
    trained.push({
      path: to,
      values: distinct,
      order: model.order,
      novel: check.novel,
      screened: screen !== null,
    })
  }

  return { trained, skipped }
}
