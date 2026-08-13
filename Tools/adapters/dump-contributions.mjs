/**
 * Dumps every adapter's raw contribution to JSON, for the Swift port to be checked against.
 *
 *     node Tools/adapters/dump-contributions.mjs
 *
 * The port has to reproduce two separable things: what each adapter *produces*, and what
 * the orchestrator then *does* with it — merge, precedence, name patterns, model training,
 * emission. Testing those together means a single mismatch anywhere shows up as one
 * undifferentiated "the corpus changed", which is the least useful failure available.
 *
 * So this freezes the boundary. With every adapter's output on disk, the Swift orchestrator
 * can be proved against the same inputs the JavaScript had, and each adapter can then be
 * ported one at a time and diffed against its own dump. A regression is attributable to a
 * single file rather than to the pipeline.
 *
 * Output is regenerable and not committed; it is a fixture for the port, not a build input.
 */
import { mkdir, readdir, writeFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

import { loadSource } from './lib/sources.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const out = join(here, 'out', 'contributions')

const { readFile } = await import('node:fs/promises')
const roster = JSON.parse(await readFile(join(here, 'locales.json'), 'utf8'))
const locales = roster.locales ?? roster
const rosterSet = new Set(locales)

/**
 * The chain rule, copied verbatim from run.mjs rather than paraphrased.
 *
 * The first draft here was a paraphrase and it was wrong in two ways: it dropped the
 * `base` special case and it filtered against the roster while building rather than at the
 * end, which changes the result for any code whose middle segment is not itself a locale.
 * Adapters receive these chains, so a wrong one produces wrong contributions and the whole
 * fixture is quietly useless.
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
const chains = Object.fromEntries(locales.map((c) => [c, fallbackChain(c, rosterSet)]))

const files = (await readdir(join(here, 'adapters'))).filter((f) => f.endsWith('.mjs')).sort()
await mkdir(out, { recursive: true })

let total = 0
for (const file of files) {
  const adapter = await import(pathToFileURL(join(here, 'adapters', file)).href)
  const sourceIds = adapter.sources ?? [adapter.source]

  const artifacts = {}
  for (const sourceId of sourceIds) {
    const { artifacts: loaded } = await loadSource(sourceId)
    Object.assign(artifacts, loaded)
  }

  const result = await adapter.run({
    artifacts,
    locales,
    chains,
    overrides: roster.cldr ?? {},
  })

  const paths = Object.values(result.contributions ?? {}).reduce(
    (n, entry) => n + Object.keys(entry).length,
    0,
  )
  total += paths
  await writeFile(
    join(out, `${adapter.id}.json`),
    JSON.stringify(
      {
        id: adapter.id,
        sources: sourceIds,
        attributeTo: adapter.attributeTo ?? sourceIds[0],
        fallback: adapter.fallback ?? false,
        contributions: result.contributions ?? {},
        sourceByLocale: result.sourceByLocale ?? null,
      },
      null,
      1,
    ),
  )
  process.stderr.write(
    `  ${adapter.id.padEnd(24)} ${String(Object.keys(result.contributions ?? {}).length).padStart(3)} locales, ${paths} paths\n`,
  )
}

process.stderr.write(`\n${files.length} adapters, ${total} contributed paths\n`)
