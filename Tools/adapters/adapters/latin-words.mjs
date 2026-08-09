/**
 * Latin vocabulary for `lorem`, from Whitaker's dictionary.
 *
 * Fills:
 *   base    lorem.word   Latin words, for filler text in every locale
 *
 * Lorem ipsum is Latin, and that turned out to be the hard part. Every permissively
 * licensed *digital edition* of a Latin text is CC BY-SA — Perseus, Wikisource, the Latin
 * WordNet — which does not compose with Apache-2.0. A dictionary is not a text, and
 * Whitaker's terms are a bare grant: "Permission is hereby freely given for any and all
 * use of program and data."
 *
 * ## Why only some entries
 *
 * `DICTLINE.GEN` is fixed-width, and its first field is a *stem* rather than a word.
 * `abbatiss` becomes `abbatissa` by adding the first-declension nominative ending, and
 * recovering that for every entry means implementing Latin morphology from the declension
 * and variant codes.
 *
 * That is skipped deliberately. Getting it subtly wrong produces strings that look like
 * Latin and are not, in a language nobody reviewing this codebase reads — the same
 * position the generative models were in with Japanese, and the same answer: take what
 * can be verified rather than what can be guessed.
 *
 * Two categories need no morphology at all. Third-declension nouns and adjectives have an
 * irregular nominative, so the dictionary stores it whole and the oblique stem separately
 * — `aequitas` beside `aequitat` — which is exactly how they can be told apart. Adverbs do
 * not decline. That leaves 1,987 words against faker's 999.
 */

import { readFile } from 'node:fs/promises'

export const id = 'latin-words'
export const source = 'whitakers-words'

/**
 * Whitaker's frequency codes, best first: A very frequent through F very rare.
 *
 * Kept to A–C so the vocabulary is words a Latinist would recognise. The tail is real
 * Latin and useless as filler — half of it appears once in the surviving corpus.
 */
const FREQUENT = new Set(['A', 'B', 'C'])

/** Field offsets in DICTLINE.GEN, which is fixed-width rather than delimited. */
const STEM1 = [0, 19]
const STEM2 = [19, 38]
const CODES = 76

export async function run({ artifacts }) {
  const text = await readFile(artifacts.dictionary, 'latin1')
  const words = new Set()
  let entries = 0

  for (const line of text.split('\n')) {
    if (line.length < 100) continue
    entries += 1

    const stem1 = line.slice(...STEM1).trim()
    const stem2 = line.slice(...STEM2).trim()
    const parts = line.slice(CODES).split(/\s+/).filter(Boolean)
    if (parts.length === 0) continue

    // AGE AREA GEO FREQ SOURCE — five single letters between the codes and the gloss.
    const flags = line.match(/\b([A-Z]) ([A-Z]) ([A-Z]) ([A-Z]) ([A-Z]) /)
    if (!flags || !FREQUENT.has(flags[4])) continue

    // Latin has no digits, no spaces inside a headword, and nothing shorter than three
    // letters worth using as filler.
    if (!/^[a-zA-Z]{3,14}$/.test(stem1)) continue

    const [pos, declension] = parts
    const nominativeIsWhole =
      (pos === 'N' || pos === 'ADJ') && declension === '3' && stem2 && stem2 !== stem1
    if (nominativeIsWhole || pos === 'ADV') words.add(stem1.toLowerCase())
  }

  if (entries < 30_000 || words.size < 1_000) {
    throw new Error(
      `Whitaker's dictionary yielded ${words.size} words from ${entries} entries — ` +
        'the fixed-width layout has changed',
    )
  }

  return {
    // `base`, not `en`. Lorem is filler rather than language: every locale that lacks its
    // own falls through to it, which is what faker's arrangement amounted to anyway.
    contributions: { base: { 'lorem.word': [...words].sort() } },
    stats: { entries, words: words.size },
  }
}
