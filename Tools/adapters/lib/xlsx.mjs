/**
 * A minimal reader for the one thing statistical offices keep publishing in: `.xlsx`.
 *
 * Four of the national name registers ship a workbook and nothing else -- Spain, Finland,
 * Sweden and the UK all publish an Excel file with no CSV beside it. That is not a format
 * anybody would choose for a build input, but refusing it means refusing the registers, so
 * this reads enough of the format to get the cells out.
 *
 * ## Why this exists rather than a dependency
 *
 * `Tools/adapters` has no package manifest and no `node_modules`, on purpose: every input
 * is a pinned file with an integrity hash, and adding a build-time dependency would put an
 * unpinned tree of somebody else's code inside the process that produces the corpus. A
 * spreadsheet reader is the kind of thing one normally installs, so it is worth saying that
 * this was weighed rather than skipped.
 *
 * ## What it supports, and what it does not
 *
 * An `.xlsx` is a ZIP holding XML. This reads the central directory, inflates the members
 * it needs with `node:zlib`, and pulls values out of `sharedStrings.xml` and the sheet XML.
 *
 * It handles what statistical publications actually contain: shared strings, inline
 * strings, numbers, and blank cells. It does not handle formulas, dates as serial numbers,
 * styles, or anything to do with presentation -- and it does not need to, because a table
 * of names and counts has none of that. A file that needs more will fail loudly on a
 * missing value rather than silently produce a wrong one.
 *
 * Row and column positions come from each cell's own reference (`B7`) rather than from
 * counting, because a sheet omits empty cells entirely: a row with a gap in it would
 * otherwise shift every value after the gap one column to the left.
 */

import { inflateRawSync } from 'node:zlib'

/** End-of-central-directory, central-directory-header, and local-file-header signatures. */
const END_OF_DIRECTORY = 0x06054b50
const DIRECTORY_ENTRY = 0x02014b50

/**
 * Reads the ZIP central directory and returns each member's name and its bytes.
 *
 * Members are found through the directory rather than by scanning for local headers,
 * because a local header may declare its sizes as zero and defer them to a trailing data
 * descriptor -- in which case scanning cannot tell where the member ends.
 */
function unzip(bytes) {
  let end = bytes.length - 22
  while (end >= 0 && bytes.readUInt32LE(end) !== END_OF_DIRECTORY) end -= 1
  if (end < 0) throw new Error('not a zip file — no end-of-central-directory record')

  const count = bytes.readUInt16LE(end + 10)
  let offset = bytes.readUInt32LE(end + 16)
  const members = new Map()

  for (let i = 0; i < count; i++) {
    if (bytes.readUInt32LE(offset) !== DIRECTORY_ENTRY) {
      throw new Error(`zip directory entry ${i} has the wrong signature`)
    }
    const method = bytes.readUInt16LE(offset + 10)
    const compressedSize = bytes.readUInt32LE(offset + 20)
    const nameLength = bytes.readUInt16LE(offset + 28)
    const extraLength = bytes.readUInt16LE(offset + 30)
    const commentLength = bytes.readUInt16LE(offset + 32)
    const localOffset = bytes.readUInt32LE(offset + 42)
    const name = bytes.subarray(offset + 46, offset + 46 + nameLength).toString('utf8')

    // The local header repeats the name and extra field, and its extra field length can
    // differ from the directory's — so the data start has to be computed from the local
    // header rather than assumed.
    const localNameLength = bytes.readUInt16LE(localOffset + 26)
    const localExtraLength = bytes.readUInt16LE(localOffset + 28)
    const dataStart = localOffset + 30 + localNameLength + localExtraLength
    const data = bytes.subarray(dataStart, dataStart + compressedSize)

    if (method === 0) members.set(name, data)
    else if (method === 8) members.set(name, inflateRawSync(data))
    else throw new Error(`${name}: compression method ${method} is not supported`)

    offset += 46 + nameLength + extraLength + commentLength
  }
  return members
}

/** XML entities that appear in spreadsheet text. Order matters: `&amp;` must be last. */
function decodeEntities(text) {
  return text
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll(/&#(\d+);/g, (_, code) => String.fromCodePoint(Number(code)))
    .replaceAll(/&#x([0-9a-fA-F]+);/g, (_, code) => String.fromCodePoint(parseInt(code, 16)))
    .replaceAll('&amp;', '&')
}

/**
 * The shared string table, which is where most cell text actually lives.
 *
 * A string entry can be split across several `<t>` runs when parts of it are formatted
 * differently, so the runs are joined rather than the first one taken. `Mª DEL CARMEN`
 * arrives in two runs in the Spanish file.
 */
function readSharedStrings(members) {
  const xml = members.get('xl/sharedStrings.xml')
  if (!xml) return []
  const text = xml.toString('utf8')
  const strings = []
  for (const [, entry] of text.matchAll(/<si>([\s\S]*?)<\/si>/g)) {
    let value = ''
    for (const [, run] of entry.matchAll(/<t[^>]*>([\s\S]*?)<\/t>/g)) value += run
    strings.push(decodeEntities(value))
  }
  return strings
}

/** `B7` -> `{ row: 7, column: 1 }`, with the column zero-based. */
function positionOf(reference) {
  const match = /^([A-Z]+)(\d+)$/.exec(reference)
  if (!match) return null
  let column = 0
  for (const character of match[1]) column = column * 26 + (character.charCodeAt(0) - 64)
  return { row: Number(match[2]), column: column - 1 }
}

/** Sheet name to its XML part, resolved through the workbook and its relationships. */
function sheetParts(members) {
  const workbook = members.get('xl/workbook.xml')?.toString('utf8') ?? ''
  const rels = members.get('xl/_rels/workbook.xml.rels')?.toString('utf8') ?? ''

  const targets = new Map()
  for (const [, id, target] of rels.matchAll(/<Relationship Id="([^"]+)"[^>]*Target="([^"]+)"/g)) {
    targets.set(id, target.replace(/^\/?xl\//, '').replace(/^\//, ''))
  }

  const parts = new Map()
  for (const [, attributes] of workbook.matchAll(/<sheet\b([^>]*)>/g)) {
    const name = /name="([^"]*)"/.exec(attributes)?.[1]
    const id = /r:id="([^"]+)"/.exec(attributes)?.[1]
    if (!name || !id) continue
    const target = targets.get(id)
    if (target) parts.set(decodeEntities(name), `xl/${target}`)
  }
  return parts
}

/**
 * Reads a workbook into `{ sheetName: rows }`, each row an array of cell strings.
 *
 * Values come back as strings whatever the cell held, because every caller here is about
 * to parse them itself and a number that arrived as `1063756` is not more trustworthy for
 * having passed through a float.
 */
export function readWorkbook(bytes) {
  const members = unzip(bytes)
  const shared = readSharedStrings(members)
  const parts = sheetParts(members)

  const sheets = {}
  for (const [name, part] of parts) {
    const xml = members.get(part)
    if (!xml) continue
    const text = xml.toString('utf8')
    const rows = []

    for (const [, cells] of text.matchAll(/<row\b[^>]*>([\s\S]*?)<\/row>/g)) {
      let row = []
      let index = null
      for (const [, attributes, body] of cells.matchAll(/<c\b([^>]*)(?:\/>|>([\s\S]*?)<\/c>)/g)) {
        const reference = /r="([A-Z]+\d+)"/.exec(attributes)?.[1]
        const position = reference ? positionOf(reference) : null
        if (position && index === null) index = position.row

        const type = /t="([^"]+)"/.exec(attributes)?.[1]
        let value = ''
        if (body) {
          if (type === 'inlineStr') {
            for (const [, run] of body.matchAll(/<t[^>]*>([\s\S]*?)<\/t>/g)) value += run
            value = decodeEntities(value)
          } else {
            const raw = /<v>([\s\S]*?)<\/v>/.exec(body)?.[1]
            if (raw !== undefined) {
              value = type === 's' ? (shared[Number(raw)] ?? '') : decodeEntities(raw)
            }
          }
        }
        // Placed by its own column rather than pushed, since empty cells are omitted from
        // the XML entirely and pushing would slide everything after a gap leftwards.
        if (position) row[position.column] = value
        else row.push(value)
      }
      row = [...row].map((cell) => cell ?? '')
      rows.push(row)
      void index
    }
    sheets[name] = rows
  }
  return sheets
}
