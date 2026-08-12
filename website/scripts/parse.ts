/**
 * Reads the generator surface out of the Swift sources.
 *
 * The reference pages are built from this rather than maintained by hand, because a
 * hand-kept list of three hundred methods is correct on the day it is written and the
 * counts in this repository have already drifted three times.
 */

import { readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'

export interface Method {
  /** The namespace, or `''` for methods on `Faker` itself. */
  ns: string
  name: string
  /** Parameters as written, so the page can show the options. */
  params: string
  /** Whether every parameter has a default, and so the method can be probed. */
  callable: boolean
}

/** Faker-level helpers that are plumbing rather than generators. */
const NOT_GENERATORS = new Set(['drawModel', 'draw', 'expand', 'resolve', 'require'])

export function readSurface(generatorsDir: string): Method[] {
  const out: Method[] = []

  for (const file of readdirSync(generatorsDir).filter((f) => f.endsWith('.swift'))) {
    const lines = readFileSync(join(generatorsDir, file), 'utf8').split('\n')
    let ns: string | null = null

    for (let i = 0; i < lines.length; i++) {
      const struct = lines[i].match(/^\s*public struct ([A-Za-z]+)Faker\b/)
      if (struct) {
        ns = struct[1][0].toLowerCase() + struct[1].slice(1)
        continue
      }
      // Methods inside `extension Faker` are top-level, not namespaced. Without this
      // they get attributed to whichever struct was last seen, which put `uuid()` on
      // `DateFaker` and produced a reference that did not compile.
      if (/^\s*(public )?extension Faker\b/.test(lines[i])) {
        ns = ''
        continue
      }

      const fn = lines[i].match(/^\s*public (?:mutating )?func ([a-z][A-Za-z0-9]*)\s*\(/)
      if (!fn || ns === null || NOT_GENERATORS.has(fn[1])) continue

      // Walk from the opening paren to its match, which may be several lines down.
      // Matching to end-of-line instead swallowed the function body and reported
      // half the surface as requiring arguments.
      let depth = 0
      let params = ''
      let k = lines[i].indexOf('(', lines[i].indexOf(fn[1]))
      outer: for (let j = i; j < lines.length; j++, k = 0) {
        for (; k < lines[j].length; k++) {
          const c = lines[j][k]
          if (c === '(') {
            depth++
            if (depth === 1) continue
          }
          if (c === ')') {
            depth--
            if (depth === 0) break outer
          }
          if (depth >= 1) params += c
        }
        params += ' '
      }
      params = params.trim().replace(/\s+/g, ' ')

      const callable =
        params === '' || params.split(/,(?![^(]*\))/).every((p) => p.includes('='))
      out.push({ ns, name: fn[1], params, callable })
    }
  }
  return out
}

/** `person.fullName` — or just `uuid` for the handful that live on `Faker`. */
export const key = (m: Method) => (m.ns ? `${m.ns}.${m.name}` : m.name)

/** `f.person.fullName()` — the call a probe program makes. */
export const call = (m: Method) => (m.ns ? `f.${m.ns}.${m.name}()` : `f.${m.name}()`)
