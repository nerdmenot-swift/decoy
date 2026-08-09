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

import { MODELLED_FIELDS, loadBlocklists, trainLocale } from './lib/models.mjs'
import { applyNamePatterns, loadNameFormats } from './lib/patterns.mjs'
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
function mergeBeneath(base, incoming, prefix, isClaimed, hasClaimBelow) {
  for (const [key, value] of Object.entries(incoming)) {
    const path = prefix ? `${prefix}.${key}` : key

    // Stop at any subtree a real adapter claimed. Descending would let stragglers the
    // adapter does not carry survive inside its table -- mime-db has 1,015 media types
    // and faker has 2 it lacks, and merging them yields a 1,017-row table stamped
    // entirely MIT/mime-db. That is the licence mislabelling this pipeline exists to
    // prevent, in miniature.
    if (isClaimed(path)) continue

    const isPlainObject =
      value !== null && typeof value === 'object' && !Array.isArray(value)

    if (!(key in base)) {
      // Copying an absent subtree wholesale would smuggle in paths a real adapter
      // claimed further down. `internet` as a whole is unclaimed, but
      // `internet.domain_suffix` is claimed in `base` — copying faker's entire
      // `internet` category into `en` therefore reinstated the six TLDs that shadowed
      // the registry's 1,438. Descend instead whenever a claim lies beneath.
      if (!(isPlainObject && hasClaimBelow(path))) {
        base[key] = value
        continue
      }
      base[key] = {}
    }
    const existing = base[key]
    const bothPlainObjects =
      existing !== null &&
      value !== null &&
      typeof existing === 'object' &&
      typeof value === 'object' &&
      !Array.isArray(existing) &&
      !Array.isArray(value)

    if (bothPlainObjects) mergeBeneath(existing, value, path, isClaimed, hasClaimBelow)
  }
  return base
}

function countStrings(value) {
  if (typeof value === 'string') return 1
  if (value === null || typeof value !== 'object') return 0
  return Object.values(value).reduce((sum, v) => sum + countStrings(v), 0)
}

async function main() {
  // Declared in one file so the compiler, the tests and CI cannot disagree about it.
  const corpusVersion = JSON.parse(
    await readFile(join(here, 'corpus-version.json'), 'utf8'),
  ).version
  if (!/^\d+\.\d+\.\d+$/.test(corpusVersion)) {
    throw new Error(`corpus-version.json holds '${corpusVersion}', which is not X.Y.Z`)
  }

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
  // Every proper ancestor of a claim, so the fallback can tell "nothing here is claimed"
  // from "something below this is" before deciding to copy a subtree wholesale.
  const claimAncestors = new Set()

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

    const { contributions, stats, sourceByLocale } = await adapter.run({
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
          //
          // A claim blocks the bootstrap in this locale, and a claim in `base` blocks it
          // everywhere. `base` is the only locale whose data is language-neutral, so a
          // claim there is a claim on the concept for every locale: top-level domains and
          // chemical elements are the same in German as in English. Without this, faker's
          // `en` copies shadowed `base` for every locale that falls through English --
          // which is all of them -- leaving the IANA adapter's 1,438 TLDs unreachable
          // behind faker's six.
          //
          // Claims in a *language* locale deliberately do not propagate down the chain.
          // Census surnames claimed in `en` must not suppress Japanese surnames in `ja`,
          // and an adapter claiming `de` must not silence `de_AT`: those are different
          // data, not the same data seen twice.
          mergeBeneath(
            merged[code],
            fragment,
            '',
            (p) => claims.has(`${code}.${p}`) || claims.has(`base.${p}`),
            (p) => claimAncestors.has(`${code}.${p}`) || claimAncestors.has(`base.${p}`),
          )
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
        for (let cut = path.lastIndexOf('.'); cut > 0; cut = path.lastIndexOf('.', cut - 1)) {
          claimAncestors.add(`${code}.${path.slice(0, cut)}`)
        }

        // A real adapter's node replaces whatever sits there, whole.
        mergeOver(merged[code], fragment)
        attribution[code][path] = sourceByLocale?.[code] ?? attributedTo
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

  // Loaded before the manifest is built, not after, because `sources` is snapshotted
  // into it by value. Loading them afterwards left LDNOOBW out of the manifest and
  // therefore out of NOTICE — an attribution failure for a CC BY 4.0 source, produced by
  // a line ordering. `decoy-validate` now checks every declared source reaches NOTICE.
  //
  // The blocklist is loaded here rather than by an adapter because no adapter uses it:
  // it screens what models produce, and models are trained at this level. Registered in
  // `sources` all the same, so it reaches the manifest and NOTICE like everything else.
  const { descriptor: screenDescriptor, artifacts: screenArtifacts } =
    await loadSource('ldnoobw')
  sources.set(screenDescriptor.id, provenanceOf(screenDescriptor))
  const blocklists = await loadBlocklists(screenArtifacts.words)

  // Name order and separator, from the CLDR release the corpus already pins. A pattern
  // is a composition rule rather than data, and this is the published authority for the
  // one part of it that varies by language.
  const { artifacts: cldrArtifacts } = await loadSource('cldr-48')
  const nameFormats = await loadNameFormats(cldrArtifacts.core, cldrArtifacts.personnames)
  let namePatterns = 0

  const manifest = {
    generator: 'decoy adapters',
    corpusVersion,
    generatedAt: new Date().toISOString().slice(0, 10),
    sources: [...sources.values()],
    // Object nodes whose keys are data. Declared by the adapters that produce them; the
    // compiler emits a `__keys` table for these and for nothing else.
    keyTables: adapters.flatMap((a) => a.keyTables ?? []).sort(),
    locales: {},
    attribution,
  }

  // Models are trained here rather than in an adapter because a model has to learn from
  // what a locale *ends up with* after the merge, not from one adapter's contribution.
  // The Census surnames win in `en` and faker's win in `de`; this code does not need to
  // know which, and will not need changing when a replacement wins instead.
  const modelStats = { locales: 0, models: 0, unscreened: [], tooSmall: 0, notViable: [] }

  let totalStrings = 0
  for (const code of locales) {
    // Already nested: every fragment is nested on the way in and merged node-wise, so
    // the `nest()` that used to sit here re-walked a tree that had no dotted keys left
    // in it.
    const definitions = merged[code] ?? {}

    const parents = (chains[code] ?? []).slice(1).map((c) => merged[c] ?? {})
    if (applyNamePatterns(code, definitions, nameFormats, parents)) {
      namePatterns += 1
      attribution[code] ??= {}
      attribution[code]['person.name'] = 'cldr-48'
    }

    const { trained, skipped } = trainLocale(code, definitions, blocklists)
    for (const reason of skipped) {
      if (reason.includes('novel')) modelStats.notViable.push(`${code} ${reason}`)
      else modelStats.tooSmall += 1
    }
    if (trained.length > 0) {
      modelStats.locales += 1
      modelStats.models += trained.length
      if (trained.some((m) => !m.screened)) modelStats.unscreened.push(code)
      for (const model of trained) {
        // A model is attributed to whatever supplied the values it learned from, because
        // that is what it is derived from. Training does not launder provenance.
        attribution[code] ??= {}
        const from = MODELLED_FIELDS.find(([, to]) => to === model.path)[0]
        const inherited = Object.entries(attribution[code])
          .filter(([path]) => from === path || from.startsWith(`${path}.`))
          .sort(([a], [b]) => b.length - a.length)[0]
        if (inherited) attribution[code][model.path] = inherited[1]
      }
    }

    await writeFile(
      join(outDir, 'locales', `${code}.json`),
      JSON.stringify(definitions, null, 0),
    )

    const ownStrings = countStrings(definitions)
    totalStrings += ownStrings
    manifest.locales[code] = {
      chain: chains[code],
      ownStrings,
    }
  }

  manifest.localeCount = locales.length
  await writeFile(join(outDir, 'manifest.json'), JSON.stringify(manifest, null, 2))

  const covered = locales.filter((c) => (manifest.locales[c].ownStrings ?? 0) > 0)
  console.log(`corpus version  : ${corpusVersion}`)
  console.log(`adapters run    : ${adapterFiles.length}`)
  console.log(`sources         : ${[...sources.keys()].join(', ')}`)
  console.log(`locales in out  : ${locales.length}`)
  console.log(`  with own data : ${covered.length}`)
  console.log(`  empty         : ${locales.length - covered.length}`)
  console.log(`strings written : ${totalStrings.toLocaleString('en-US')}`)
  console.log(`name patterns   : ${namePatterns} locales, from CLDR`)
  console.log(
    `models trained  : ${modelStats.models} across ${modelStats.locales} locales`,
  )
  console.log(
    `  refused       : ${modelStats.tooSmall} below the training floor, ` +
      `${modelStats.notViable.length} could not generate`,
  )
  for (const reason of modelStats.notViable.slice(0, 6)) {
    console.log(`      ${reason}`)
  }
  if (modelStats.notViable.length > 6) {
    console.log(`      … ${modelStats.notViable.length - 6} more`)
  }
  if (modelStats.unscreened.length > 0) {
    console.log(
      `  no blocklist  : ${modelStats.unscreened.length} locales ` +
        `(${modelStats.unscreened.slice(0, 8).join(', ')}${modelStats.unscreened.length > 8 ? ', …' : ''})`,
    )
  }
}

await main()
