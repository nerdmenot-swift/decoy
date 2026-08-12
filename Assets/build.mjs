#!/usr/bin/env node
/**
 * Builds Decoy's brand assets from computed geometry.
 *
 *     node Assets/build.mjs
 *
 * Node built-ins only -- no npm, no package manifest, no node_modules, matching the
 * rule the adapter pipeline already follows. That is why the PNG encoder and the
 * polygon rasteriser are in this file rather than being `sharp`: the whole point of a
 * toolchain that takes no dependencies is not to take one for a favicon.
 *
 * Nothing here is hand-drawn. Every proportion is a ratio of the brim width, the straw
 * fan is generated from mirrored angles, and the letterforms are constructed from rings
 * and strokes on one monoline grid -- which is what gives the mark exact symmetry and
 * ties the wordmark's weight to the mark's by construction rather than by eye.
 *
 * A system font's outlines cannot be licensed into a distributed logo, and SVG <text>
 * renders only where the font happens to be installed -- nowhere that matters, GitHub
 * included. Hence drawing the five letters.
 */

import { deflateSync } from 'node:zlib'
import { writeFileSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------

/**
 * Brand colours are graphic fills, so they answer to the eye. The *text* tokens in
 * `docs`-facing surfaces are held to WCAG AA instead, which is why `#328191` is not
 * among them: it measures 4.21:1 on paper and so may carry shapes and large headings
 * but not body text. `checkContrast()` at the bottom asserts the rest.
 */
export const MARK = { teal: '#328191', cream: '#F2EDE1', amber: '#E0A029', ink: '#12171E' }
// Lifted for dark grounds: #328191 sits too close to #0F1216 to hold an edge.
export const MARK_DARK = { teal: '#5AAEC0', cream: '#EDE7DA', amber: '#E0A029', ink: '#EDE7DA' }

export const TEXT_LIGHT = {
  paper: '#F8F8F5', card: '#FFFFFF', ink: '#12171E', muted: '#5B5F63', faint: '#6F716D',
  rule: '#DEDCD5', accent: '#2C7382', 'accent-soft': '#E4EFF1',
  caution: '#8F6114', 'caution-soft': '#F6EEDF',
}
export const TEXT_DARK = {
  paper: '#0F1216', card: '#171B20', ink: '#E9E7E2', muted: '#9BA0A6', faint: '#7C8086',
  rule: '#262B31', accent: '#5AAEC0', 'accent-soft': '#17262B',
  caution: '#E0A029', 'caution-soft': '#241D10',
}

// ---------------------------------------------------------------------------
// The mark
// ---------------------------------------------------------------------------

const MARK_DEFAULTS = {
  crownH: 0.27, bandH: 0.11, brimH: 0.13,
  topW: 0.48, midW: 0.53, baseW: 0.57,
  strawLen: 0.42, rootSpread: 0.15, baseHW: 0.058, tipHW: 0.038,
  angles: [-48, -24, 0, 24, 48],
}

/** Returns `[{ points, fill }]` with the origin at the crown's top centre. */
export function markShapes(W, colours, opts = {}) {
  const o = { ...MARK_DEFAULTS, ...opts }
  const ch = o.crownH * W, bh = o.bandH * W, mh = o.brimH * W, sl = o.strawLen * W
  const y1 = ch, y2 = ch + bh, y3 = ch + bh + mh
  const out = []

  // Straw first, so the brim paints over the joins.
  const n = o.angles.length
  o.angles.forEach((deg, i) => {
    const t = (deg * Math.PI) / 180
    const rx = ((i - (n - 1) / 2) / ((n - 1) / 2)) * o.rootSpread * W
    const ry = y3 - mh * 0.6                       // rooted inside the brim
    const tx = rx + sl * Math.sin(t), ty = ry + sl * Math.cos(t)
    const px = Math.cos(t), py = -Math.sin(t)      // perpendicular to the wedge axis
    const b = o.baseHW * W, k = o.tipHW * W
    out.push({
      fill: colours.amber,
      points: [[rx + b * px, ry + b * py], [tx + k * px, ty + k * py],
               [tx - k * px, ty - k * py], [rx - b * px, ry - b * py]],
    })
  })

  const tw = (o.topW * W) / 2, mw = (o.midW * W) / 2, bw = (o.baseW * W) / 2
  out.push({ fill: colours.teal, points: [[-tw, 0], [tw, 0], [mw, y1], [-mw, y1]] })
  out.push({ fill: colours.cream, points: [[-mw, y1], [mw, y1], [bw, y2], [-bw, y2]] })
  out.push({ fill: colours.teal, points: [[-W / 2, y2], [W / 2, y2], [W / 2, y3], [-W / 2, y3]] })
  return out
}

/** Square viewBox around the shapes, padded proportionally so every asset keeps the
 *  same optical margin instead of being cropped differently per size. */
function squareBox(shapes, padRatio) {
  const xs = shapes.flatMap((s) => s.points.map((p) => p[0]))
  const ys = shapes.flatMap((s) => s.points.map((p) => p[1]))
  const x0 = Math.min(...xs), x1 = Math.max(...xs)
  const y0 = Math.min(...ys), y1 = Math.max(...ys)
  const w = x1 - x0, h = y1 - y0
  const side = Math.max(w, h) * (1 + 2 * padRatio)
  return { x: x0 - (side - w) / 2, y: y0 - (side - h) / 2, side }
}

const f = (n) => n.toFixed(2)

function markSVG(shapes, padRatio) {
  const { x, y, side } = squareBox(shapes, padRatio)
  const body = shapes.map((s) =>
    `<polygon points="${s.points.map(([a, b]) => `${f(a)},${f(b)}`).join(' ')}" fill="${s.fill}"/>`
  ).join('')
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${f(x)} ${f(y)} ${f(side)} ${f(side)}">${body}</svg>\n`
}

// ---------------------------------------------------------------------------
// Rasteriser and PNG encoder
// ---------------------------------------------------------------------------

/** Scanline polygon fill with even-odd parity, painted in order at `ss` times the
 *  target size and box-filtered down. Every shape here is a simple quad, so parity
 *  fill is exact and the supersample is what antialiases the straw's diagonals. */
function rasterise(shapes, size, padRatio, ss = 8) {
  const { x: vx, y: vy, side } = squareBox(shapes, padRatio)
  const big = size * ss
  const buf = new Uint8Array(big * big * 4)          // RGBA, zeroed = transparent

  for (const shape of shapes) {
    const [r, g, b] = hexToRGB(shape.fill)
    const pts = shape.points.map(([px, py]) => [
      ((px - vx) / side) * big, ((py - vy) / side) * big,
    ])
    const ys = pts.map((p) => p[1])
    const yStart = Math.max(0, Math.floor(Math.min(...ys)))
    const yEnd = Math.min(big - 1, Math.ceil(Math.max(...ys)))

    for (let y = yStart; y <= yEnd; y++) {
      const sy = y + 0.5
      const xs = []
      for (let i = 0; i < pts.length; i++) {
        const [x1, y1] = pts[i], [x2, y2] = pts[(i + 1) % pts.length]
        if ((y1 <= sy && y2 > sy) || (y2 <= sy && y1 > sy)) {
          xs.push(x1 + ((sy - y1) / (y2 - y1)) * (x2 - x1))
        }
      }
      xs.sort((a, c) => a - c)
      for (let i = 0; i + 1 < xs.length; i += 2) {
        const from = Math.max(0, Math.ceil(xs[i] - 0.5))
        const to = Math.min(big - 1, Math.floor(xs[i + 1] - 0.5))
        for (let x = from; x <= to; x++) {
          const o = (y * big + x) * 4
          buf[o] = r; buf[o + 1] = g; buf[o + 2] = b; buf[o + 3] = 255
        }
      }
    }
  }

  // Box filter down. Averaging premultiplied colour keeps edges from fringing toward
  // black where they meet transparency.
  const out = new Uint8Array(size * size * 4)
  const area = ss * ss
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      let R = 0, G = 0, B = 0, A = 0
      for (let dy = 0; dy < ss; dy++) {
        for (let dx = 0; dx < ss; dx++) {
          const o = ((y * ss + dy) * big + x * ss + dx) * 4
          const a = buf[o + 3] / 255
          R += buf[o] * a; G += buf[o + 1] * a; B += buf[o + 2] * a; A += a
        }
      }
      const o = (y * size + x) * 4
      out[o] = A ? Math.round(R / A) : 0
      out[o + 1] = A ? Math.round(G / A) : 0
      out[o + 2] = A ? Math.round(B / A) : 0
      out[o + 3] = Math.round((A / area) * 255)
    }
  }
  return out
}

const hexToRGB = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16))

const CRC_TABLE = (() => {
  const t = new Int32Array(256)
  for (let n = 0; n < 256; n++) {
    let c = n
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
    t[n] = c
  }
  return t
})()

function crc32(buf) {
  let c = -1
  for (const byte of buf) c = CRC_TABLE[(c ^ byte) & 0xff] ^ (c >>> 8)
  return (c ^ -1) >>> 0
}

function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length)
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data])
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(body))
  return Buffer.concat([len, body, crc])
}

/** Minimal RGBA PNG: one IHDR, one IDAT of unfiltered scanlines, one IEND. */
function encodePNG(size, rgba) {
  const raw = Buffer.alloc((size * 4 + 1) * size)
  for (let y = 0; y < size; y++) {
    raw[y * (size * 4 + 1)] = 0                    // filter type 0, none
    Buffer.from(rgba.buffer, y * size * 4, size * 4).copy(raw, y * (size * 4 + 1) + 1)
  }
  const ihdr = Buffer.alloc(13)
  ihdr.writeUInt32BE(size, 0); ihdr.writeUInt32BE(size, 4)
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0   // 8-bit RGBA
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ])
}

// ---------------------------------------------------------------------------
// The wordmark
// ---------------------------------------------------------------------------

const X = 100                 // x-height
const SW = 0.185 * X          // stroke weight
const ASC = 0.42 * X          // ascender above x-height (the `d` stem)
const DESC = 0.44 * X         // descender below baseline (the `y` tail)
const GAP = 0.13 * X          // sidebearing; round letters carry their own air
const R = X / 2               // bowl radius

const at = (cx, cy, r, deg) => {
  const t = (deg * Math.PI) / 180
  return [cx + r * Math.cos(t), cy - r * Math.sin(t)]   // y grows downward
}

/** Outer circle plus a counter wound the other way, so nonzero fill leaves it hollow
 *  while still unioning cleanly with any stroke laid across it. Even-odd would XOR
 *  the overlap and punch holes where the `e` bar and the `d` stem cross their bowls. */
const ring = (cx, cy, ro, ri) =>
  `M${f(cx - ro)},${f(cy)}A${f(ro)},${f(ro)} 0 1 0 ${f(cx + ro)},${f(cy)}` +
  `A${f(ro)},${f(ro)} 0 1 0 ${f(cx - ro)},${f(cy)}Z` +
  `M${f(cx - ri)},${f(cy)}A${f(ri)},${f(ri)} 0 1 1 ${f(cx + ri)},${f(cy)}` +
  `A${f(ri)},${f(ri)} 0 1 1 ${f(cx - ri)},${f(cy)}Z`

/** Open ring segment from a0 to a1, counterclockwise on screen. */
function arcSeg(cx, cy, ro, ri, a0, a1) {
  const large = ((a1 - a0 + 360) % 360) > 180 ? 1 : 0
  const [ox0, oy0] = at(cx, cy, ro, a0), [ox1, oy1] = at(cx, cy, ro, a1)
  const [ix0, iy0] = at(cx, cy, ri, a0), [ix1, iy1] = at(cx, cy, ri, a1)
  return `M${f(ox0)},${f(oy0)}A${f(ro)},${f(ro)} 0 ${large} 0 ${f(ox1)},${f(oy1)}` +
         `L${f(ix1)},${f(iy1)}A${f(ri)},${f(ri)} 0 ${large} 1 ${f(ix0)},${f(iy0)}Z`
}

/** A thick straight stroke between two points. */
function stroke(x0, y0, x1, y1, w) {
  const dx = x1 - x0, dy = y1 - y0, n = Math.hypot(dx, dy)
  const px = (-dy / n) * (w / 2), py = (dx / n) * (w / 2)
  return `M${f(x0 + px)},${f(y0 + py)}L${f(x1 + px)},${f(y1 + py)}` +
         `L${f(x1 - px)},${f(y1 - py)}L${f(x0 - px)},${f(y0 - py)}Z`
}

/** Returns `[path, advance]`. The baseline sits at y = X. */
function letter(ch, x) {
  const ro = R, ri = R - SW, cy = X - R
  switch (ch) {
    case 'o': return [ring(x + R, cy, ro, ri), X]
    case 'c': return [arcSeg(x + R, cy, ro, ri, 52, -52), X]
    case 'e':
      // The stroke runs from the bar's right terminal anticlockwise round to the
      // lower-right aperture; the bar closes the counter and ends the stroke.
      return [arcSeg(x + R, cy, ro, ri, 0, -48) +
              stroke(x + R - ro, cy, x + R + ro * 0.97, cy, SW), X]
    case 'd':
      return [ring(x + R, cy, ro, ri) +
              stroke(x + X - SW / 2, -ASC, x + X - SW / 2, X, SW), X]
    case 'y': {
      // The right stroke runs unbroken into the descender; the left arm meets it. The
      // junction is solved for rather than eyeballed -- a plausible-looking point left
      // the two strokes ten units apart and the letter came out visibly broken.
      const topR = x + X - SW * 0.5, tipX = x + X * 0.26, tipY = X + DESC
      const jy = X * 0.6
      const jx = topR + (jy / tipY) * (tipX - topR)
      return [stroke(topR, 0, tipX, tipY, SW) + stroke(x + SW * 0.5, 0, jx, jy, SW), X * 0.94]
    }
    default: throw new Error(`no glyph for ${ch}`)
  }
}

// Optical kerning: `o` and `y` both carry their mass away from the join, so the metric
// gap reads far wider than it measures.
const KERN = { oy: -0.06 * X, ec: -0.02 * X, co: -0.02 * X }

export function wordmark(colour) {
  const word = 'decoy'
  const paths = []
  let x = 0
  for (let i = 0; i < word.length; i++) {
    const [d, adv] = letter(word[i], x)
    paths.push(d)
    x += adv + GAP + (KERN[word.slice(i, i + 2)] ?? 0)
  }
  return {
    body: `<path d="${paths.join('')}" fill="${colour}" fill-rule="nonzero"/>`,
    width: x - GAP, top: -ASC, bottom: X + DESC,
  }
}

// ---------------------------------------------------------------------------
// Lockups
// ---------------------------------------------------------------------------

const MARK_H = 1.86      // mark height as a multiple of the wordmark x-height
const LOCKUP_GAP = 0.34  // gap between mark and word, as a fraction of mark width

export function lockup(colours, ink, stacked = false) {
  const shapes = markShapes(176, colours)
  const xs = shapes.flatMap((s) => s.points.map((p) => p[0]))
  const ys = shapes.flatMap((s) => s.points.map((p) => p[1]))
  const mx0 = Math.min(...xs), my0 = Math.min(...ys)
  const mw = Math.max(...xs) - mx0, mh = Math.max(...ys) - my0
  const s = (MARK_H * X) / mh
  const sw = mw * s, sh = mh * s

  const word = wordmark(ink)
  const wh = word.bottom - word.top
  let totalW, totalH, mx, my, wx, wy

  if (stacked) {
    const gap = 0.17 * sh
    totalW = Math.max(sw, word.width); totalH = sh + gap + wh
    mx = (totalW - sw) / 2; my = 0
    wx = (totalW - word.width) / 2; wy = sh + gap - word.top
  } else {
    const gap = LOCKUP_GAP * sw
    totalW = sw + gap + word.width; totalH = Math.max(sh, wh)
    mx = 0; my = (totalH - sh) / 2
    // Optically centred on the x-height band rather than the full ascender-to-descender
    // box: the `d` stem and the `y` tail are thin and carry little weight.
    wx = sw + gap; wy = (totalH - X) / 2
  }

  const marks = shapes.map((sh_) =>
    `<polygon points="${sh_.points
      .map(([px, py]) => `${f((px - mx0) * s + mx)},${f((py - my0) * s + my)}`)
      .join(' ')}" fill="${sh_.fill}"/>`).join('')
  return {
    content: marks + `<g transform="translate(${f(wx)},${f(wy)})">${word.body}</g>`,
    width: totalW, height: totalH,
  }
}

function wrap(content, w, h, padRatio = 0.08, extra = '') {
  const pad = Math.max(w, h) * padRatio
  return `<svg xmlns="http://www.w3.org/2000/svg" ${extra}viewBox="${f(-pad)} ${f(-pad)} ` +
         `${f(w + 2 * pad)} ${f(h + 2 * pad)}">${content}</svg>\n`
}

// ---------------------------------------------------------------------------
// Contrast self-check
// ---------------------------------------------------------------------------

const luminance = (hex) => {
  const [r, g, b] = hexToRGB(hex).map((v) => {
    const c = v / 255
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
  })
  return 0.2126 * r + 0.7152 * g + 0.0722 * b
}

const contrast = (a, b) => {
  const [la, lb] = [luminance(a), luminance(b)]
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
}

/**
 * Fails the build when a text token drops below WCAG AA against its own ground.
 *
 * Here rather than in a document because a palette written down is a palette that
 * drifts. The mark's own colours are exempt: they are graphic fills, and `#328191`
 * measures 4.21:1, which is why a darkened sibling carries links and body text.
 */
function checkContrast() {
  const problems = []
  for (const [name, tokens] of [['light', TEXT_LIGHT], ['dark', TEXT_DARK]]) {
    for (const key of ['ink', 'muted', 'faint', 'accent', 'caution']) {
      const ratio = contrast(tokens[key], tokens.paper)
      if (ratio < 4.5) problems.push(`${name}.${key} ${tokens[key]} = ${ratio.toFixed(2)}:1`)
    }
  }
  if (problems.length) {
    console.error('contrast below AA:\n  ' + problems.join('\n  '))
    process.exit(1)
  }
  console.log('  contrast        all text tokens >= 4.5:1')
}

// ---------------------------------------------------------------------------
// Build
// ---------------------------------------------------------------------------

// The icon keeps the straw. That was tested rather than assumed, and the assumption was
// wrong: a strawless reduction reads as a shelf at 16px, because what survives is not
// the wedges but the amber mass beneath the brim -- the mark's only colour contrast, and
// the thing that makes it findable in a tab strip. Shorter, fatter wedges hold the grid.
const ICON = { strawLen: 0.36, baseHW: 0.068, tipHW: 0.046 }

const VARIANTS = [
  { name: 'logo', colours: MARK, opts: {}, pad: 0.10, sizes: [512, 1024] },
  { name: 'logo-dark', colours: MARK_DARK, opts: {}, pad: 0.10, sizes: [512, 1024] },
  { name: 'icon', colours: MARK, opts: ICON, pad: 0.05, sizes: [16, 32, 48, 180, 512] },
  { name: 'icon-dark', colours: MARK_DARK, opts: ICON, pad: 0.05, sizes: [16, 32, 180, 512] },
]

function build() {
  mkdirSync(HERE, { recursive: true })
  const write = (name, data) => {
    writeFileSync(join(HERE, name), data)
    return name
  }

  for (const v of VARIANTS) {
    const shapes = markShapes(176, v.colours, v.opts)
    write(`${v.name}.svg`, markSVG(shapes, v.pad))
    for (const size of v.sizes) {
      write(`${v.name}-${size}.png`, encodePNG(size, rasterise(shapes, size, v.pad)))
    }
    console.log(`  ${v.name.padEnd(16)}svg + ${v.sizes.length} png`)
  }

  // Lockups and the wordmark ship as SVG only. They are set as text-like artwork with
  // arcs, and rasterising a logo is a downgrade unless a specific pixel size is
  // demanded -- which is true of favicons and of nothing else here.
  for (const [name, colours, ink, stacked] of [
    ['lockup', MARK, MARK.ink, false],
    ['lockup-dark', MARK_DARK, MARK_DARK.ink, false],
    ['lockup-stacked', MARK, MARK.ink, true],
    ['lockup-stacked-dark', MARK_DARK, MARK_DARK.ink, true],
  ]) {
    const { content, width, height } = lockup(colours, ink, stacked)
    write(`${name}.svg`, wrap(content, width, height))
    console.log(`  ${name.padEnd(16)}svg  ${Math.round(width)} wide`)
  }

  for (const [name, ink] of [['wordmark', MARK.ink], ['wordmark-dark', MARK_DARK.ink]]) {
    const w = wordmark(ink)
    write(`${name}.svg`,
      wrap(`<g transform="translate(0,${f(-w.top)})">${w.body}</g>`, w.width, w.bottom - w.top))
    console.log(`  ${name.padEnd(16)}svg  ${Math.round(w.width)} wide`)
  }

  checkContrast()
}

if (import.meta.url === `file://${process.argv[1]}`) build()
