/**
 * Fetches and verifies the upstream artifacts an adapter declares.
 *
 * The verification is the point. A corpus whose provenance is "someone downloaded a
 * file once" is exactly what Decoy is replacing, so every artifact is pinned to an
 * integrity hash and a silently-changed upstream fails the build rather than quietly
 * altering everyone's fixtures.
 */

import { createHash } from 'node:crypto'
import { execFile } from 'node:child_process'
import { mkdir, readFile, readdir, rm, stat, writeFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { promisify } from 'node:util'

const run = promisify(execFile)
const here = dirname(fileURLToPath(import.meta.url))
const root = join(here, '..')
const cacheDir = join(root, '.cache')

/** Parses an SRI string such as `sha512-Base64==` into its parts. */
function parseIntegrity(integrity) {
  const separator = integrity.indexOf('-')
  if (separator < 0) throw new Error(`malformed integrity string: ${integrity}`)
  return {
    algorithm: integrity.slice(0, separator),
    expected: integrity.slice(separator + 1),
  }
}

function digest(buffer, algorithm) {
  return createHash(algorithm).update(buffer).digest('base64')
}

async function exists(path) {
  try {
    await stat(path)
    return true
  } catch {
    return false
  }
}

/**
 * Downloads an artifact, or reuses the cached copy when it still matches its hash.
 *
 * A cached file is re-verified rather than trusted: a corrupted or tampered cache would
 * otherwise produce a corpus that passes every check on the machine that built it and
 * nowhere else.
 */
async function acquire(sourceId, artifact) {
  const { algorithm, expected } = parseIntegrity(artifact.integrity)
  await mkdir(cacheDir, { recursive: true })
  const suffix =
    artifact.format === 'file'
      ? artifact.filename
      : `${artifact.name}.${artifact.format === 'zip' ? 'zip' : 'tgz'}`
  const cached = join(cacheDir, `${sourceId}-${suffix}`)

  if (await exists(cached)) {
    const buffer = await readFile(cached)
    if (digest(buffer, algorithm) === expected) return cached
    await rm(cached, { force: true })
  }

  process.stderr.write(`  fetching ${artifact.url}\n`)
  const response = await fetch(artifact.url)
  if (!response.ok) {
    throw new Error(`${artifact.url} returned HTTP ${response.status}`)
  }
  const buffer = Buffer.from(await response.arrayBuffer())

  const actual = digest(buffer, algorithm)
  if (actual !== expected) {
    throw new Error(
      `integrity mismatch for ${artifact.url}\n` +
        `  expected ${algorithm}-${expected}\n` +
        `  actual   ${algorithm}-${actual}\n` +
        `Upstream changed under a pinned version. Verify the change is legitimate, then ` +
        `update the integrity hash in sources/${sourceId}.json.`,
    )
  }

  await writeFile(cached, buffer)
  return cached
}

/**
 * Unpacks a tarball with the system `tar`.
 *
 * Deliberately not an npm dependency: these adapters are the mechanism for removing
 * Decoy's reliance on somebody else's package, so the toolchain that builds the corpus
 * should not itself accumulate a dependency tree.
 */
async function extract(archive, destination, format) {
  await rm(destination, { recursive: true, force: true })
  await mkdir(destination, { recursive: true })
  // `tar` handles zip on macOS via libarchive but not with GNU tar on Linux, so zips go
  // through `unzip` explicitly rather than relying on which tar the host happens to have.
  if (format === 'zip') await run('unzip', ['-q', '-o', archive, '-d', destination])
  else await run('tar', ['xzf', archive, '-C', destination])
  return destination
}

/** Loads a source descriptor and unpacks every artifact it declares. */
export async function loadSource(sourceId) {
  const descriptor = JSON.parse(
    await readFile(join(root, 'sources', `${sourceId}.json`), 'utf8'),
  )

  const required = ['id', 'license', 'url', 'version', 'retrieved', 'artifacts']
  for (const field of required) {
    if (descriptor[field] === undefined) {
      throw new Error(`sources/${sourceId}.json is missing required field '${field}'`)
    }
  }

  const artifacts = {}
  for (const artifact of descriptor.artifacts) {
    const path = await acquire(descriptor.id, artifact)

    // A bare file is handed over as-is; anything else is a tarball to unpack. Both
    // resolve to a path the adapter reads, so adapters do not care which they got.
    artifacts[artifact.name] =
      artifact.format === 'file'
        ? path
        : await extract(
            path,
            join(cacheDir, `${descriptor.id}-${artifact.name}`),
            artifact.format,
          )
  }

  return { descriptor, artifacts }
}

/** The provenance record that travels with the data into the compiled corpus. */
export function provenanceOf(descriptor) {
  return {
    id: descriptor.id,
    license: descriptor.license,
    url: descriptor.url,
    version: descriptor.version,
    retrieved: descriptor.retrieved,
  }
}

export { readdir, readFile }
