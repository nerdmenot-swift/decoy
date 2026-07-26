/**
 * Dumps the @faker-js/faker locale corpus to JSON.
 *
 * Deliberately a dumper rather than a parser. faker-js ships its corpus as plain
 * TypeScript objects; importing the built package and serialising it is robust
 * against upstream refactors in a way that parsing .ts source never is, and it can
 * be re-run to pick up upstream improvements.
 *
 * Output (all regenerable, none of it committed):
 *   out/locales/<code>.json  unmerged definitions for one locale
 *   out/manifest.json        locale metadata + fallback chains + stats
 *   out/LICENSE.faker-js     upstream MIT notice, retained for attribution
 */

import { createRequire } from 'node:module'
import { mkdir, readFile, rm, writeFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

import { allFakers, allLocales } from '@faker-js/faker'

const require = createRequire(import.meta.url)
const here = dirname(fileURLToPath(import.meta.url))
const outDir = join(here, 'out')

/**
 * Reproduces faker-js's locale fallback order: the locale itself, then its base
 * language, then English, then the language-neutral `base` locale.
 *
 * This is asserted against faker's own merged output below rather than trusted --
 * if upstream changes the rule, the extractor fails loudly instead of silently
 * emitting a corpus with the wrong inheritance.
 */
function fallbackChain(code) {
  // `base` is the root of the hierarchy and inherits from nothing. Giving it an
  // `en` fallback would quietly pull English data into every locale on earth.
  if (code === 'base') return ['base']

  // Strip one underscore-separated segment at a time, so `en_AU_ocker` resolves
  // through `en_AU` before reaching `en` rather than skipping straight past it.
  const parts = code.split('_')
  const chain = []
  for (let i = parts.length; i > 0; i--) chain.push(parts.slice(0, i).join('_'))

  if (!chain.includes('en')) chain.push('en')
  chain.push('base')
  return chain.filter((c, i) => c in allLocales && chain.indexOf(c) === i)
}

/** Merges definitions along a chain; the earliest locale to define a key wins. */
function mergeChain(chain) {
  const merged = {}
  for (const code of chain) {
    const locale = allLocales[code]
    for (const [category, entries] of Object.entries(locale)) {
      if (entries === null || typeof entries !== 'object') continue
      merged[category] ??= {}
      for (const [key, value] of Object.entries(entries)) {
        // Presence, not nullishness. An explicit `null` means "this locale has no
        // such concept" -- Azerbaijani has no name prefixes -- and must *block*
        // the fallback rather than invite English to fill the gap.
        if (!(key in merged[category])) merged[category][key] = value
      }
    }
  }
  return merged
}

function deepEqual(a, b) {
  if (a === b) return true
  if (a === null || b === null || typeof a !== 'object' || typeof b !== 'object') return false
  if (Array.isArray(a) !== Array.isArray(b)) return false
  const aKeys = Object.keys(a)
  const bKeys = Object.keys(b)
  if (aKeys.length !== bKeys.length) return false
  return aKeys.every((k) => deepEqual(a[k], b[k]))
}

/** Counts leaf strings, so the manifest can report real corpus depth per locale. */
function countStrings(value) {
  if (typeof value === 'string') return 1
  if (value === null || typeof value !== 'object') return 0
  return Object.values(value).reduce((sum, v) => sum + countStrings(v), 0)
}

async function main() {
  await rm(outDir, { recursive: true, force: true })
  await mkdir(join(outDir, 'locales'), { recursive: true })

  const codes = Object.keys(allLocales).sort()
  const manifest = { generator: 'decoy extractor', locales: {} }
  const mismatches = []

  for (const code of codes) {
    const chain = fallbackChain(code)

    // Verify the chain rule against faker's own resolution before trusting it.
    const expected = allFakers[code]?.rawDefinitions
    if (expected) {
      const actual = mergeChain(chain)
      for (const category of Object.keys(expected)) {
        if (!deepEqual(actual[category], expected[category])) {
          mismatches.push(`${code}.${category}`)
        }
      }
    }

    const definitions = allLocales[code]
    await writeFile(
      join(outDir, 'locales', `${code}.json`),
      JSON.stringify(definitions, null, 0),
    )

    manifest.locales[code] = {
      chain,
      metadata: definitions.metadata ?? null,
      categories: Object.keys(definitions).filter((c) => c !== 'metadata').sort(),
      ownStrings: countStrings(definitions),
      resolvedStrings: countStrings(mergeChain(chain)),
    }
  }

  // Retain the upstream copyright notice next to the data it covers.
  const fakerLicense = join(dirname(require.resolve('@faker-js/faker/package.json')), 'LICENSE')
  await writeFile(join(outDir, 'LICENSE.faker-js'), await readFile(fakerLicense, 'utf8'))

  manifest.fakerVersion = require('@faker-js/faker/package.json').version
  manifest.localeCount = codes.length
  // Day granularity, not a timestamp: provenance needs a retrieval date, but a
  // per-second stamp would make two extracts of the same upstream differ.
  manifest.extractedAt = new Date().toISOString().slice(0, 10)
  await writeFile(join(outDir, 'manifest.json'), JSON.stringify(manifest, null, 2))

  const totalOwn = codes.reduce((s, c) => s + manifest.locales[c].ownStrings, 0)
  console.log(`faker-js version : ${manifest.fakerVersion}`)
  console.log(`locales written  : ${codes.length}`)
  console.log(`total strings    : ${totalOwn.toLocaleString('en-US')} (unmerged)`)
  console.log(`en resolved      : ${manifest.locales.en.resolvedStrings.toLocaleString('en-US')}`)
  console.log(`de resolved      : ${manifest.locales.de.resolvedStrings.toLocaleString('en-US')}`)

  if (mismatches.length > 0) {
    console.error(`\nFALLBACK CHAIN MISMATCH in ${mismatches.length} category/locale pairs.`)
    console.error(`First 20: ${mismatches.slice(0, 20).join(', ')}`)
    console.error('The derived chain no longer matches faker-js resolution; fix fallbackChain().')
    process.exitCode = 1
  } else {
    console.log(`\nfallback chains verified against faker's own resolution for all locales.`)
  }
}

await main()
