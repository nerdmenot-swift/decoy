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

/**
 * Removes lines an upstream re-issues without meaning, so the digest covers the data.
 *
 * IANA regenerates the root zone file with a fresh serial comment whenever the zone is
 * republished, whether or not any TLD changed -- the file went from serial 2026080600 to
 * 2026080700 with all 1,438 entries byte-identical. Pinning the raw bytes would fail the
 * build daily for no reason, and a check that cries wolf every morning is one everybody
 * learns to bypass.
 *
 * Only the ignored lines go unverified, and they are metadata by construction. Every
 * line that becomes corpus data is still covered, so a TLD appearing or disappearing --
 * or being injected -- still fails.
 */
function normalise(buffer, ignorePattern) {
  if (!ignorePattern) return buffer
  const pattern = new RegExp(ignorePattern)
  const kept = buffer
    .toString('utf8')
    .split('\n')
    .filter((line) => !pattern.test(line))
  return Buffer.from(kept.join('\n'), 'utf8')
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
 * Fetches an artifact, retrying the failures that are the network rather than the server.
 *
 * There was no retry here at all, which made every build as reliable as the least reliable
 * host in the source list on the day it ran. Azerbaijan's Ministry of Justice endpoint is
 * what exposed it: it answers in under a second most of the time and occasionally does not
 * answer within Node's ten-second connect timeout, so a build that had worked all week
 * failed once and would have looked like a broken pin rather than a blip.
 *
 * A 4xx is not retried. That is the server saying the request is wrong -- a moved file, a
 * revoked dataset -- and asking again four times only delays the report. 5xx and transport
 * failures are, because those are the ones that come right on their own.
 *
 * The integrity hash still decides whether what arrives is correct. This only decides how
 * many times to ask.
 */
async function fetchWithRetry(url, attempts = 4) {
  let lastError = null
  for (let attempt = 0; attempt < attempts; attempt++) {
    try {
      const response = await fetch(url)
      if (response.ok) return Buffer.from(await response.arrayBuffer())
      if (response.status >= 400 && response.status < 500) {
        throw new Error(`${url} returned HTTP ${response.status}`)
      }
      lastError = new Error(`${url} returned HTTP ${response.status}`)
    } catch (error) {
      if (error instanceof Error && /returned HTTP 4/.test(error.message)) throw error
      lastError = error
    }
    if (attempt < attempts - 1) {
      await new Promise((resolve) => setTimeout(resolve, 3000 * (attempt + 1)))
    }
  }
  throw new Error(
    `${url} failed after ${attempts} attempts — ${lastError?.message ?? 'no response'}`,
  )
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
  const contentDigest = (buffer) =>
    digest(normalise(buffer, artifact.ignoreLinesMatching), algorithm)
  await mkdir(cacheDir, { recursive: true })
  const suffix =
    artifact.format === 'file'
      ? artifact.filename
      : `${artifact.name}.${{ zip: 'zip', 'tar.xz': 'tar.xz' }[artifact.format] ?? 'tgz'}`
  const cached = join(cacheDir, `${sourceId}-${suffix}`)

  if (await exists(cached)) {
    const buffer = await readFile(cached)
    if (contentDigest(buffer) === expected) return cached
    await rm(cached, { force: true })
  }

  // A vendored copy, for upstreams that cannot be fetched from a build machine.
  //
  // avoindata.suomi.fi answers 403 from its load balancer to every client outside whatever
  // it considers acceptable -- GitHub's runners, and this laptop. It is one of fifty-one
  // pinned artifacts and the only one affected, but a cold clone could not build the corpus
  // at all because of it, on any platform.
  //
  // Vendoring does not weaken anything: the hash below still decides whether the bytes are
  // right, exactly as it does for a download, so a tampered vendored file fails the same
  // way a tampered cache does. It is checked after the cache and before the network, so a
  // reachable upstream is still preferred once the cache is warm.
  const vendored = join(root, 'vendor', `${sourceId}-${suffix}`)
  if (await exists(vendored)) {
    const buffer = await readFile(vendored)
    if (digest(normalise(buffer, artifact.ignoreLinesMatching), algorithm) === expected) {
      process.stderr.write(`  vendored ${sourceId}/${artifact.name ?? suffix}\n`)
      await writeFile(cached, buffer)
      return cached
    }
    throw new Error(
      `integrity mismatch for vendored ${vendored}\n` +
        `Re-vendor from the pinned URL, or delete the file to fetch it.`,
    )
  }

  process.stderr.write(`  fetching ${artifact.url}\n`)
  const buffer = await fetchWithRetry(artifact.url)

  const actual = contentDigest(buffer)
  if (actual !== expected) {
    throw new Error(
      `integrity mismatch for ${artifact.url}\n` +
        `  expected ${algorithm}-${expected}\n` +
        `  actual   ${algorithm}-${actual}\n` +
        `Upstream changed under a pinned version. Verify the change is legitimate, then ` +
        `update the integrity hash in sources/${sourceId}.json.` +
        (artifact.ignoreLinesMatching
          ? `\n(The digest ignores lines matching /${artifact.ignoreLinesMatching}/, so this ` +
            `is a real content change, not a re-issue.)`
          : ''),
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
  else if (format === 'tar.xz') await run('tar', ['xJf', archive, '-C', destination])
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
    // Transcribed from the upstream's own licence file. Without it no MIT copyright
    // line, CC BY creator attribution or WordNet-style notice can be emitted at all,
    // because this is the only place a holder is ever recorded.
    copyright: descriptor.copyright ?? '',
    url: descriptor.url,
    version: descriptor.version,
    retrieved: descriptor.retrieved,
  }
}
