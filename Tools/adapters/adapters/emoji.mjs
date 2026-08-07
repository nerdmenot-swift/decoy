/**
 * Emoji by category, from the Unicode emoji data files.
 *
 * Emoji are the same everywhere, so this lives in `base`.
 *
 * Fills:
 *   base    internet.emoji.<category>   for the ten categories the generator draws from
 */

import { readFile } from 'node:fs/promises'

export const id = 'emoji'
export const source = 'unicode-emoji'

/**
 * Unicode's groups, mapped to the categories `internet.emoji(_:)` accepts.
 *
 * `People & Body` is split, because the generator distinguishes a body part from a
 * person and Unicode does not — it separates them by subgroup instead.
 */
const CATEGORY_FOR_GROUP = {
  'Smileys & Emotion': 'smiley',
  'Animals & Nature': 'nature',
  'Food & Drink': 'food',
  'Travel & Places': 'travel',
  Activities: 'activity',
  Objects: 'object',
  Symbols: 'symbol',
  Flags: 'flag',
}

/** Subgroups of `People & Body` that are anatomy rather than people. */
function isBodyPart(subgroup) {
  return subgroup.startsWith('hand') || subgroup === 'body-parts'
}

export async function run({ artifacts }) {
  const text = await readFile(artifacts.emoji, 'utf8')

  const byCategory = {}
  let group = ''
  let subgroup = ''
  let skipped = 0

  for (const line of text.split('\n')) {
    if (line.startsWith('# group:')) {
      group = line.slice('# group:'.length).trim()
      continue
    }
    if (line.startsWith('# subgroup:')) {
      subgroup = line.slice('# subgroup:'.length).trim()
      continue
    }
    if (line === '' || line.startsWith('#')) continue

    // Only fully-qualified sequences. The file also lists minimally-qualified and
    // unqualified forms of the same emoji -- sequences missing a variation selector,
    // which render inconsistently and are present so parsers can recognise them, not so
    // anything emits them.
    if (!/;\s*fully-qualified/.test(line)) continue

    // `Component` is skin-tone swatches and hair colours: modifiers, not emoji anybody
    // sends on their own.
    if (group === 'Component') {
      skipped += 1
      continue
    }

    const category =
      CATEGORY_FOR_GROUP[group]
      ?? (group === 'People & Body' ? (isBodyPart(subgroup) ? 'body' : 'person') : null)
    if (category === null) {
      skipped += 1
      continue
    }

    // The emoji itself is the first token after the `# ` that follows the status field.
    const emoji = line.split('#')[1]?.trim().split(/\s+/)[0]
    if (!emoji) continue

    ;(byCategory[category] ??= []).push(emoji)
  }

  const categories = Object.keys(byCategory).sort()
  if (categories.length !== 10) {
    throw new Error(
      `expected 10 emoji categories, got ${categories.length} (${categories.join(', ')}) — `
        + `the group taxonomy has changed`,
    )
  }

  const contributions = { base: {} }
  for (const category of categories) {
    // Deduplicated: a handful of sequences appear under more than one subgroup.
    contributions.base[`internet.emoji.${category}`] = [...new Set(byCategory[category])]
  }

  return {
    contributions,
    stats: {
      total: Object.values(byCategory).reduce((sum, list) => sum + list.length, 0),
      categories: categories.length,
      skipped,
    },
  }
}
