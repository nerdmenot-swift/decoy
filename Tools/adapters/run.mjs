/**
 * Builds the intermediate corpus JSON from adapters.
 *
 * Every source, including the faker-js bootstrap, is a pinned artifact fetched by URL
 * and verified against an integrity hash. Nothing is installed, nothing is vendored, and
 * there is no package manifest -- these are plain `.mjs` files node runs directly, which
 * is the whole toolchain.
 *
 * faker-js is one adapter among several and the lowest-precedence one, so it is deleted
 * a field at a time as other adapters cover its ground rather than in one frightening
 * commit.
 *
 * Run with `node run.mjs`.
 *
 * Output (regenerable, none of it committed):
 *   out/locales/<code>.json  nested definitions for one locale
 *   out/manifest.json        chains, source records, and per-path attribution
 */

import { mkdir, readdir, readFile, rm, writeFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

import { loadSource, provenanceOf } from './lib/sources.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const outDir = join(here, 'out')

/**
 * The locale fallback rule: the locale itself, then each shorter prefix of it, then
 * English, then the language-neutral base.
 *
 * Derived rather than stored so it cannot drift out of sync with the roster. `base` is
 * the root and inherits from nothing -- giving it an `en` fallback would quietly pull
 * English into every locale on earth.
 */
function fallbackChain(code, roster) {
  if (code === 'base') return ['base']

  const parts = code.split('_')
  const chain = []
  for (let i = parts.length; i > 0; i--) chain.push(parts.slice(0, i).join('_'))

  if (!chain.includes('en')) chain.push('en')
  chain.push('base')
  return chain.filter((c, i) => roster.has(c) && chain.indexOf(c) === i)
}

/** Expands `{ "location.country": [...] }` into the nested shape the compiler walks. */
function nest(flat) {
  const root = {}
  for (const [path, value] of Object.entries(flat)) {
    const segments = path.split('.')
    let node = root
    for (const segment of segments.slice(0, -1)) {
      node[segment] ??= {}
      node = node[segment]
    }
    node[segments.at(-1)] = value
  }
  return root
}

/**
 * Merges `incoming` into `base`, letting `incoming` win at every node it supplies.
 *
 * How a real adapter's contribution lands. Intermediate objects are descended into, so
 * two adapters writing `system.mime_type` and `system.programming_language` both land
 * without either clobbering the other's branch.
 */
function mergeOver(base, incoming) {
  for (const [key, value] of Object.entries(incoming)) {
    const existing = base[key]
    const bothPlainObjects =
      existing !== null &&
      value !== null &&
      typeof existing === 'object' &&
      typeof value === 'object' &&
      !Array.isArray(existing) &&
      !Array.isArray(value)

    if (bothPlainObjects) mergeOver(existing, value)
    else base[key] = value
  }
  return base
}

/**
 * Merges `incoming` into `base` without overwriting anything already there.
 *
 * How the bootstrap corpus is laid underneath the adapters: it fills the gaps and never
 * displaces. Arrays are values, not containers -- merging two string tables element-wise
 * would produce a list that neither source ever contained.
 */
function mergeBeneath(base, incoming, prefix, isClaimed) {
  for (const [key, value] of Object.entries(incoming)) {
    const path = prefix ? `${prefix}.${key}` : key

    // Stop at any subtree a real adapter claimed. Descending would let stragglers the
    // adapter does not carry survive inside its table -- mime-db has 1,015 media types
    // and faker has 2 it lacks, and merging them yields a 1,017-row table stamped
    // entirely MIT/mime-db. That is the licence mislabelling this pipeline exists to
    // prevent, in miniature.
    if (isClaimed(path)) continue

    if (!(key in base)) {
      base[key] = value
      continue
    }
    const existing = base[key]
    const bothPlainObjects =
      existing !== null &&
      value !== null &&
      typeof existing === 'object' &&
      typeof value === 'object' &&
      !Array.isArray(existing) &&
      !Array.isArray(value)

    if (bothPlainObjects) mergeBeneath(existing, value, path, isClaimed)
  }
  return base
}

function countStrings(value) {
  if (typeof value === 'string') return 1
  if (value === null || typeof value !== 'object') return 0
  return Object.values(value).reduce((sum, v) => sum + countStrings(v), 0)
}

async function main() {
  const roster = JSON.parse(await readFile(join(here, 'locales.json'), 'utf8'))
  const locales = roster.locales
  const rosterSet = new Set(locales)

  const adapterFiles = (await readdir(join(here, 'adapters')))
    .filter((f) => f.endsWith('.mjs'))
    .sort()

  // Load every adapter before running any, so fallbacks can be ordered last regardless
  // of filename. `faker-js.mjs` sorts near the front alphabetically and must not.
  const adapters = []
  for (const file of adapterFiles) {
    adapters.push(await import(join(here, 'adapters', file)))
  }
  adapters.sort((a, b) => (a.fallback ? 1 : 0) - (b.fallback ? 1 : 0))

  // Chains are derived once and handed to adapters: the faker adapter checks them
  // against faker's own resolution, which is the only independent confirmation the rule
  // has while faker-js is still a source.
  const chains = Object.fromEntries(locales.map((c) => [c, fallbackChain(c, rosterSet)]))

  const merged = {}       // code -> nested definitions
  const attribution = {}  // code -> { claimed path -> sourceId }
  const sources = new Map()
  const claims = new Set()  // "<code>.<path>" claimed by a non-fallback adapter

  for (const adapter of adapters) {

    // An adapter may combine sources -- currencies take their names and symbols from
    // CLDR and their numeric codes from the ISO 4217 registry.
    const sourceIds = adapter.sources ?? [adapter.source]
    process.stderr.write(`adapter ${adapter.id} (${sourceIds.join(' + ')})\n`)

    const artifacts = {}
    for (const sourceId of sourceIds) {
      const { descriptor, artifacts: loaded } = await loadSource(sourceId)
      sources.set(descriptor.id, provenanceOf(descriptor))
      for (const [name, path] of Object.entries(loaded)) {
        if (name in artifacts) {
          throw new Error(
            `${adapter.id}: two of its sources both name an artifact '${name}'`,
          )
        }
        artifacts[name] = path
      }
    }

    // The format stores one source per table, so a table merged from several sources is
    // credited to the one the adapter names as primary. Every source it used is still
    // registered in the corpus and listed here, so nothing is lost -- the attribution is
    // just coarser than per-field. Splitting it would be a format change.
    const attributedTo = adapter.attributeTo ?? sourceIds[0]

    const { contributions, stats } = await adapter.run({
      artifacts,
      locales,
      chains,
      overrides: roster.cldr ?? {},
    })

    for (const [code, paths] of Object.entries(contributions)) {
      if (!rosterSet.has(code)) {
        throw new Error(`${adapter.id} produced locale '${code}', which is not in the roster`)
      }
      merged[code] ??= {}
      attribution[code] ??= {}

      for (const [path, value] of Object.entries(paths)) {
        const fragment = nest({ [path]: value })

        if (adapter.fallback) {
          // Laid underneath: contributes only where nothing has been supplied yet.
          // Losing to a real adapter is not a conflict, it is the migration working,
          // and it happens hundreds of times per run.
          mergeBeneath(merged[code], fragment, '', (p) => claims.has(`${code}.${p}`))
          attribution[code][path] ??= attributedTo
          continue
        }

        // Two *equal-precedence* adapters claiming one path is a decision about which
        // source wins, and it has to be made deliberately rather than by filename order.
        const claim = `${code}.${path}`
        if (claims.has(claim)) {
          throw new Error(
            `${adapter.id} and ${attribution[code][path]} both define ${claim}`,
          )
        }
        claims.add(claim)

        // A real adapter's node replaces whatever sits there, whole.
        mergeOver(merged[code], fragment)
        attribution[code][path] = attributedTo
      }
    }

    if (stats) {
      const parts = Object.entries(stats)
        .filter(([, v]) => !Array.isArray(v) || v.length > 0)
        .map(([k, v]) => `${k}=${Array.isArray(v) ? v.join(',') : v}`)
      process.stderr.write(`  ${parts.join(' ')}\n`)
    }
  }

  await rm(outDir, { recursive: true, force: true })
  await mkdir(join(outDir, 'locales'), { recursive: true })

  const manifest = {
    generator: 'decoy adapters',
    generatedAt: new Date().toISOString().slice(0, 10),
    sources: [...sources.values()],
    locales: {},
    attribution,
  }

  let totalStrings = 0
  for (const code of locales) {
    const flat = merged[code] ?? {}
    const definitions = nest(flat)
    await writeFile(
      join(outDir, 'locales', `${code}.json`),
      JSON.stringify(definitions, null, 0),
    )

    const ownStrings = countStrings(definitions)
    totalStrings += ownStrings
    manifest.locales[code] = {
      chain: chains[code],
      categories: Object.keys(definitions).sort(),
      ownStrings,
      paths: Object.keys(flat).sort(),
    }
  }

  manifest.localeCount = locales.length
  await writeFile(join(outDir, 'manifest.json'), JSON.stringify(manifest, null, 2))

  const covered = locales.filter((c) => (manifest.locales[c].ownStrings ?? 0) > 0)
  console.log(`adapters run    : ${adapterFiles.length}`)
  console.log(`sources         : ${[...sources.keys()].join(', ')}`)
  console.log(`locales in out  : ${locales.length}`)
  console.log(`  with own data : ${covered.length}`)
  console.log(`  empty         : ${locales.length - covered.length}`)
  console.log(`strings written : ${totalStrings.toLocaleString('en-US')}`)
}

await main()
