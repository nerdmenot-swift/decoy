/**
 * Job titles, from the US Department of Labor's occupational taxonomy.
 *
 * Fills:
 *   en   person.job_title   1,016 occupations somebody is actually employed in
 *
 * faker composed job titles from three interchangeable lists — a descriptor, an area and
 * a type — which produces "Lead Solutions Engineer" and also "Dynamic Infrastructure
 * Officer", "Global Applications Agent" and several thousand other strings that name no
 * job anyone holds. O*NET is the list of jobs that exist.
 *
 * `jobTitle()` already prefers a flat list where a locale has one; that was wired up when
 * `decoy-validate` found two locales carrying `person.job_title` and nothing reading it.
 */

import { readFile, readdir } from 'node:fs/promises'
import { join } from 'node:path'

export const id = 'occupations'
export const source = 'onet'

export async function run({ artifacts }) {
  const [root] = await readdir(artifacts.database)
  const text = await readFile(join(artifacts.database, root, 'Occupation Data.txt'), 'utf8')

  const lines = text.split('\n')
  const header = lines[0].split('\t')
  if (header[1] !== 'Title') {
    throw new Error(`O*NET header is ${header.join('|')} — the schema has changed`)
  }

  const titles = new Set()
  for (const line of lines.slice(1)) {
    const [, title] = line.split('\t')
    // "All Other" is O*NET's residual bucket for occupations too small to code
    // separately -- "Managers, All Other" is a category, not a job title.
    if (!title || /, All Other$/.test(title.trim())) continue
    titles.add(title.trim())
  }

  if (titles.size < 500) {
    throw new Error(`O*NET yielded ${titles.size} occupations — verify before re-pinning`)
  }

  return {
    contributions: { en: { 'person.job_title': [...titles].sort() } },
    stats: { occupations: titles.size },
  }
}
