/**
 * Composition rules, derived from CLDR rather than inherited from faker.
 *
 * A pattern is not data in the way a name list is. `{{person.firstName}}
 * {{person.lastName}}` contains no names — it says how a locale assembles one, which is a
 * fact about the language with a published authority behind it. CLDR is that authority,
 * and it agrees with faker everywhere the two overlap: Hungarian, Japanese, Korean and
 * Chinese put the surname first in both, and everything else does not.
 *
 * A pipeline stage rather than an adapter for the same reason the model trainer is one —
 * whether a locale gets a prefix variant depends on whether it *has* prefixes, and that is
 * only knowable after the merge.
 */

import { readFile, readdir } from 'node:fs/promises'
import { join } from 'node:path'

/**
 * Loads the two things CLDR knows that faker's patterns encoded implicitly: which order a
 * locale writes names in, and what goes between the parts.
 *
 * The separator is not always a space. CLDR's `nativeSpaceReplacement` is empty for
 * Japanese, Korean and Chinese, because 山田太郎 is how a Japanese name is written and
 * 山田 太郎 is a concession to Latin typesetting. faker used a space for Japanese; CLDR
 * is the authority and this follows it.
 */
export async function loadNameFormats(coreDir, personNamesDir) {
  const defaults = JSON.parse(
    await readFile(join(coreDir, 'package', 'supplemental', 'personNamesDefaults.json'), 'utf8'),
  ).supplemental.personNamesDefaults

  const surnameFirst = new Set((defaults.surnameFirst ?? '').split(/\s+/).filter(Boolean))

  const separators = new Map()
  const base = join(personNamesDir, 'package', 'main')
  for (const locale of await readdir(base)) {
    try {
      const parsed = JSON.parse(
        await readFile(join(base, locale, 'personNames.json'), 'utf8'),
      ).main[locale].personNames
      if (typeof parsed.nativeSpaceReplacement === 'string') {
        separators.set(locale, parsed.nativeSpaceReplacement)
      }
    } catch (error) {
      if (error.code !== 'ENOENT') throw error
    }
  }

  if (surnameFirst.size === 0 || separators.size < 50) {
    throw new Error(
      `CLDR name formats look wrong: ${surnameFirst.size} surname-first, ` +
        `${separators.size} separators — verify before re-pinning`,
    )
  }
  return { surnameFirst, separators }
}

/** CLDR keys on language, so `de_AT` and `pt_BR` resolve through their language. */
function formatFor({ surnameFirst, separators }, code) {
  const language = code.split('_')[0]
  return {
    surnameFirst: surnameFirst.has(language),
    separator: separators.get(code.replace('_', '-')) ?? separators.get(language) ?? ' ',
  }
}

/**
 * What a locale says about a path: `filled`, `empty`, or `absent`.
 *
 * The three-way answer is the point. `null` means the locale declares it deliberately
 * empty, which **blocks** inheritance — Azerbaijani has no honorifics, and the whole
 * reason the corpus format carries explicit nulls is to stop it borrowing English ones.
 * Collapsing `empty` into `absent` makes a chain walk continue past a stop sign.
 */
function stateOf(definitions, path) {
  let cursor = definitions
  for (const part of path.split('.')) {
    if (cursor === null || typeof cursor !== 'object' || !(part in cursor)) return 'absent'
    cursor = cursor[part]
  }
  if (cursor === null) return 'empty'
  if (Array.isArray(cursor)) return cursor.length > 0 ? 'filled' : 'empty'
  return typeof cursor === 'object' ? 'filled' : 'absent'
}

/**
 * Builds `person.name` for one locale.
 *
 * Weighted so the plain form dominates, because it does in life: a fixture set where one
 * row in eight carries a title looks generated. faker weighted `en` at 49 plain against 7
 * titled and 3 suffixed, and these are the same proportions rounded.
 *
 * Prefix and suffix variants only where the locale has that data *and* writes names with
 * a space. Attaching a title in a script that joins its name parts is a question about
 * that language which CLDR's default patterns do not answer, and guessing it would put
 * さん in the wrong place rather than leave it out.
 */
export function namePattern(resolves, format) {
  const given = '{{person.firstName}}'
  const surname = '{{person.lastName}}'
  const [first, second] = format.surnameFirst ? [surname, given] : [given, surname]
  const plain = `${first}${format.separator}${second}`

  const variants = [{ value: plain, weight: 90 }]
  if (format.separator === ' ') {
    if (resolves('person.prefix')) {
      variants.push({ value: `{{person.prefix}} ${plain}`, weight: 7 })
    }
    if (resolves('person.suffix')) {
      variants.push({ value: `${plain} {{person.suffix}}`, weight: 3 })
    }
  }
  return variants
}

/**
 * Rewrites `person.name` for every locale that has names at all.
 *
 * Returns the codes it claimed, so the run can attribute them and report the count.
 */
export function applyNamePatterns(code, definitions, formats, chain = []) {
  // Resolved through the chain, and stopping where the chain says to stop.
  //
  // Two failures, both found by the validator rather than by reading. Checking only the
  // locale's own data left `en_GB` and `en_HK` on faker's pattern, because both define
  // surnames and inherit given names. And walking the chain *without* honouring explicit
  // nulls gave Azerbaijani a `{{person.prefix}}` variant on the strength of English
  // honorifics it deliberately blocks — a token that expands to nothing in the one locale
  // the blocking mechanism was built for.
  const resolves = (path) => {
    for (const level of [definitions, ...chain]) {
      const state = stateOf(level, path)
      if (state === 'filled') return true
      if (state === 'empty') return false
    }
    return false
  }

  // A pattern referencing a name nothing in the chain supplies would trap at the call
  // site rather than fail the build, which is why this is checked at all.
  if (!resolves('person.first_name') || !resolves('person.last_name')) return false

  definitions.person ??= {}
  definitions.person.name = namePattern(resolves, formatFor(formats, code))
  return true
}
