/**
 * Builds the intermediate corpus JSON from adapters.
 *
 * This is the replacement for Tools/extractor: the extractor dumps somebody else's
 * corpus, whereas this runs programs that derive data from pinned, citable primary
 * sources and records where every path came from. Both write the same shape, so the
 * Swift compiler downstream does not care which produced its input -- which is what lets
 * faker-js be deleted one field at a time rather than in one frightening commit.
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

  const merged = {}       // code -> { path -> value }
  const attribution = {}  // code -> { path -> sourceId }
  const sources = new Map()

  for (const file of adapterFiles) {
    const adapter = await import(join(here, 'adapters', file))

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
      overrides: roster.cldr ?? {},
    })

    for (const [code, paths] of Object.entries(contributions)) {
      if (!rosterSet.has(code)) {
        throw new Error(`${adapter.id} produced locale '${code}', which is not in the roster`)
      }
      merged[code] ??= {}
      attribution[code] ??= {}
      for (const [path, value] of Object.entries(paths)) {
        // Two adapters claiming one path is a decision about which source wins, and it
        // must be made deliberately rather than by filename order.
        if (path in merged[code]) {
          throw new Error(
            `${adapter.id} and ${attribution[code][path]} both define ${code}.${path}`,
          )
        }
        merged[code][path] = value
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
      chain: fallbackChain(code, rosterSet),
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
