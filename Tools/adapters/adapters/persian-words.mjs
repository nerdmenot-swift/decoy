/**
 * Persian vocabulary, from the Lilak spell-checking dictionary.
 *
 * Fills:
 *   fa    lorem.word
 *
 * What this replaces is worth stating, because it is not a marginal improvement. faker's
 * Persian `lorem.word` is 89 entries reading `لورم ایپسوم متن ساختگی` — the Persian
 * transliteration of "lorem ipsum fake text". It is placeholder text *about* being
 * placeholder text, not Persian vocabulary. Any fixture using it produced the same four
 * words over and over.
 *
 * Only `lorem.word`. Hunspell dictionaries carry affix flags, not part-of-speech tags, so
 * there is no basis for filling `word.noun` or `word.verb`; putting unclassified words
 * there would be a quiet untruth of exactly the kind this pipeline exists to prevent.
 */

import { readFile } from 'node:fs/promises'
import { join } from 'node:path'

export const id = 'persian-words'
export const source = 'lilak'

/**
 * How many words to keep, shortest first.
 *
 * The dictionary has 63,641 clean single words, which is two orders of magnitude more
 * than filler text needs and would put more Persian in the corpus than English. Hunspell
 * carries no frequency data to rank by, so the ranking is length, on Zipf's law of
 * abbreviation: across languages, more frequent words are shorter. That is a proxy and
 * is stated as one — it is weaker than the Census counts behind `person.last_name` or
 * the sense counts behind `word.noun`, and it is the best signal this format offers.
 */
const KEEP = 10_000
const MINIMUM_LENGTH = 3

export async function run({ artifacts }) {
  const text = await readFile(
    join(artifacts.lilak, 'fa-IR', 'fa-IR.dic'),
    'utf8',
  )

  // The first line of a .dic file is the entry count, not an entry.
  const lines = text.split('\n').slice(1)

  const words = []
  for (const line of lines) {
    // `word/FLAGS` — the affix flags describe inflection and are not part of the word.
    const word = line.split('/')[0].trim()
    if (word === '') continue

    // Latin letters and digits mark abbreviations and units; the zero-width non-joiner
    // marks multi-part compounds that read as two words.
    if (/[0-9A-Za-z.‌]/.test(word)) continue
    if (/\s/.test(word)) continue
    if (word.length < MINIMUM_LENGTH) continue

    words.push(word)
  }

  if (words.length < 10_000) {
    throw new Error(`Lilak yielded only ${words.length} words — the format has changed`)
  }

  const kept = [...new Set(words)]
    .sort((a, b) => a.length - b.length || (a < b ? -1 : 1))
    .slice(0, KEEP)
    .sort()

  return {
    contributions: {
      fa: { 'lorem.word': kept },
    },
    stats: { available: words.length, kept: kept.length },
  }
}
