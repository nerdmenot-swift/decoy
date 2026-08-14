import DecoyAdapterKit
import Foundation

/// Builds Decoy's brand assets from computed geometry.
///
///     swift run decoy-assets
///
/// Nothing here is hand-drawn. Every proportion is a ratio of the brim width, the straw fan
/// is generated from mirrored angles, and the letterforms are constructed from rings and
/// strokes on one monoline grid — which is what gives the mark exact symmetry and ties the
/// wordmark's weight to the mark's by construction rather than by eye.
///
/// A system font's outlines cannot be licensed into a distributed logo, and SVG `<text>`
/// renders only where the font happens to be installed — nowhere that matters, GitHub
/// included. Hence drawing the five letters.
///
/// ## The one thing it shells out for
///
/// PNG's IDAT chunk is a zlib stream, and Swift has no portable zlib. Rather than take a
/// dependency or hand-roll DEFLATE for a favicon, this asks `gzip` — which is already how
/// the corpus build unpacks archives, through the same `Shell`.
///
/// gzip's container is a 10-byte header, the raw deflate stream, and an 8-byte trailer;
/// zlib's is a 2-byte header, the same deflate stream, and an Adler-32. So the stream is
/// reframed rather than recompressed.
///
/// The compressed bytes are not identical to what Node produced — GNU gzip and zlib are
/// separate implementations of the same format and make marginally different choices, which
/// here happen to come out about 0.6% smaller. Every decoded pixel *is* identical, across
/// all thirteen images, which is the claim that matters: the geometry, the 8× supersampling
/// and the box filter all reproduce exactly, and only the packing of the result changed.

// MARK: - Palette

/// Brand colours are graphic fills, so they answer to the eye. The *text* tokens are held
/// to WCAG AA instead, which is why `#328191` is not among them: it measures 4.21:1 and so
/// may carry shapes and large headings but not body text. `checkContrast` asserts the rest.
enum Palette {
    static let mark = (teal: "#328191", cream: "#F2EDE1", amber: "#E0A029", ink: "#12171E")
    /// Lifted for dark grounds: `#328191` sits too close to `#0F1216` to hold an edge.
    static let markDark = (teal: "#5AAEC0", cream: "#EDE7DA", amber: "#E0A029", ink: "#EDE7DA")

    static let textLight: [(String, String)] = [
        ("paper", "#F8F8F5"), ("card", "#FFFFFF"), ("ink", "#12171E"), ("muted", "#5B5F63"),
        ("faint", "#6F716D"), ("rule", "#DEDCD5"), ("accent", "#2C7382"),
        ("accent-soft", "#E4EFF1"), ("caution", "#8F6114"), ("caution-soft", "#F6EEDF"),
    ]
    static let textDark: [(String, String)] = [
        ("paper", "#0F1216"), ("card", "#171B20"), ("ink", "#E9E7E2"), ("muted", "#9BA0A6"),
        ("faint", "#7C8086"), ("rule", "#262B31"), ("accent", "#5AAEC0"),
        ("accent-soft", "#17262B"), ("caution", "#E0A029"), ("caution-soft", "#241D10"),
    ]
}

typealias Colours = (teal: String, cream: String, amber: String, ink: String)

func hexToRGB(_ hex: String) -> (r: Int, g: Int, b: Int) {
    let digits = Array(hex.dropFirst())
    func byte(_ start: Int) -> Int {
        Int(String(digits[start..<(start + 2)]), radix: 16) ?? 0
    }
    return (byte(0), byte(2), byte(4))
}

/// `Number.prototype.toFixed(2)`.
///
/// Not `String(format: "%.2f")`, which rounds ties to even where JavaScript rounds them
/// away from zero. Every coordinate in every SVG goes through this, so a single tie
/// resolved the other way is a file that differs for no visible reason.
func f(_ value: Double) -> String {
    let magnitude = (abs(value) * 100).rounded(.toNearestOrAwayFromZero) / 100
    let text = String(format: "%.2f", magnitude)
    return value < 0 && magnitude != 0 ? "-" + text : text
}

// MARK: - The mark

struct Shape {
    let points: [(x: Double, y: Double)]
    let fill: String
}

struct MarkOptions {
    var crownH = 0.27
    var bandH = 0.11
    var brimH = 0.13
    var topW = 0.48
    var midW = 0.53
    var baseW = 0.57
    var strawLen = 0.42
    var rootSpread = 0.15
    var baseHW = 0.058
    var tipHW = 0.038
    var angles: [Double] = [-48, -24, 0, 24, 48]
}

/// A scarecrow's hat with straw beneath it, and no face — for a library that generates
/// people who do not exist. The absence under the brim is the idea.
///
/// Returns the shapes with the origin at the crown's top centre.
func markShapes(_ W: Double, _ colours: Colours, _ o: MarkOptions = MarkOptions()) -> [Shape] {
    let ch = o.crownH * W
    let bh = o.bandH * W
    let mh = o.brimH * W
    let sl = o.strawLen * W
    let y1 = ch
    let y2 = ch + bh
    let y3 = ch + bh + mh
    var out: [Shape] = []

    // Straw first, so the brim paints over the joins.
    let n = Double(o.angles.count)
    for (index, deg) in o.angles.enumerated() {
        let t = deg * Double.pi / 180
        let rx = ((Double(index) - (n - 1) / 2) / ((n - 1) / 2)) * o.rootSpread * W
        let ry = y3 - mh * 0.6  // rooted inside the brim
        let tx = rx + sl * sin(t)
        let ty = ry + sl * cos(t)
        let px = cos(t)
        let py = -sin(t)  // perpendicular to the wedge axis
        let b = o.baseHW * W
        let k = o.tipHW * W
        out.append(
            Shape(
                points: [
                    (rx + b * px, ry + b * py), (tx + k * px, ty + k * py),
                    (tx - k * px, ty - k * py), (rx - b * px, ry - b * py),
                ], fill: colours.amber))
    }

    let tw = (o.topW * W) / 2
    let mw = (o.midW * W) / 2
    let bw = (o.baseW * W) / 2
    out.append(Shape(points: [(-tw, 0), (tw, 0), (mw, y1), (-mw, y1)], fill: colours.teal))
    out.append(Shape(points: [(-mw, y1), (mw, y1), (bw, y2), (-bw, y2)], fill: colours.cream))
    out.append(
        Shape(points: [(-W / 2, y2), (W / 2, y2), (W / 2, y3), (-W / 2, y3)], fill: colours.teal))
    return out
}

/// Square viewBox around the shapes, padded proportionally so every asset keeps the same
/// optical margin instead of being cropped differently per size.
func squareBox(_ shapes: [Shape], _ padRatio: Double) -> (x: Double, y: Double, side: Double) {
    let xs = shapes.flatMap { $0.points.map(\.x) }
    let ys = shapes.flatMap { $0.points.map(\.y) }
    let x0 = xs.min() ?? 0
    let x1 = xs.max() ?? 0
    let y0 = ys.min() ?? 0
    let y1 = ys.max() ?? 0
    let w = x1 - x0
    let h = y1 - y0
    let side = max(w, h) * (1 + 2 * padRatio)
    return (x0 - (side - w) / 2, y0 - (side - h) / 2, side)
}

func markSVG(_ shapes: [Shape], _ padRatio: Double) -> String {
    let box = squareBox(shapes, padRatio)
    let body = shapes.map { shape in
        let points = shape.points.map { "\(f($0.x)),\(f($0.y))" }.joined(separator: " ")
        return "<polygon points=\"\(points)\" fill=\"\(shape.fill)\"/>"
    }.joined()
    return
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"\(f(box.x)) \(f(box.y)) "
        + "\(f(box.side)) \(f(box.side))\">\(body)</svg>\n"
}

// MARK: - Rasteriser

/// Scanline polygon fill with even-odd parity, painted in order at `ss` times the target
/// size and box-filtered down.
func rasterise(_ shapes: [Shape], size: Int, padRatio: Double, ss: Int = 8) -> [UInt8] {
    let box = squareBox(shapes, padRatio)
    let big = size * ss
    var buf = [UInt8](repeating: 0, count: big * big * 4)  // RGBA, zeroed = transparent

    for shape in shapes {
        let (r, g, b) = hexToRGB(shape.fill)
        let pts = shape.points.map { point in
            (
                x: ((point.x - box.x) / box.side) * Double(big),
                y: ((point.y - box.y) / box.side) * Double(big)
            )
        }
        let ys = pts.map(\.y)
        let yStart = max(0, Int((ys.min() ?? 0).rounded(.down)))
        let yEnd = min(big - 1, Int((ys.max() ?? 0).rounded(.up)))
        guard yStart <= yEnd else { continue }

        for y in yStart...yEnd {
            let sy = Double(y) + 0.5
            var xs: [Double] = []
            for index in pts.indices {
                let (x1, y1) = pts[index]
                let (x2, y2) = pts[(index + 1) % pts.count]
                if (y1 <= sy && y2 > sy) || (y2 <= sy && y1 > sy) {
                    xs.append(x1 + ((sy - y1) / (y2 - y1)) * (x2 - x1))
                }
            }
            xs.sort()
            var index = 0
            while index + 1 < xs.count {
                let from = max(0, Int((xs[index] - 0.5).rounded(.up)))
                let to = min(big - 1, Int((xs[index + 1] - 0.5).rounded(.down)))
                if from <= to {
                    for x in from...to {
                        let offset = (y * big + x) * 4
                        buf[offset] = UInt8(r)
                        buf[offset + 1] = UInt8(g)
                        buf[offset + 2] = UInt8(b)
                        buf[offset + 3] = 255
                    }
                }
                index += 2
            }
        }
    }

    // Box filter down. Averaging premultiplied colour keeps edges from fringing toward
    // black where they meet transparency.
    var out = [UInt8](repeating: 0, count: size * size * 4)
    let area = Double(ss * ss)
    for y in 0..<size {
        for x in 0..<size {
            var R = 0.0
            var G = 0.0
            var B = 0.0
            var A = 0.0
            for dy in 0..<ss {
                for dx in 0..<ss {
                    let offset = ((y * ss + dy) * big + x * ss + dx) * 4
                    let a = Double(buf[offset + 3]) / 255
                    R += Double(buf[offset]) * a
                    G += Double(buf[offset + 1]) * a
                    B += Double(buf[offset + 2]) * a
                    A += a
                }
            }
            let offset = (y * size + x) * 4
            out[offset] = A != 0 ? UInt8((R / A).rounded(.toNearestOrAwayFromZero)) : 0
            out[offset + 1] = A != 0 ? UInt8((G / A).rounded(.toNearestOrAwayFromZero)) : 0
            out[offset + 2] = A != 0 ? UInt8((B / A).rounded(.toNearestOrAwayFromZero)) : 0
            out[offset + 3] = UInt8(((A / area) * 255).rounded(.toNearestOrAwayFromZero))
        }
    }
    return out
}

// MARK: - PNG

let crcTable: [UInt32] = (0..<256).map { n in
    var c = UInt32(n)
    for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
    return c
}

func crc32(_ bytes: [UInt8]) -> UInt32 {
    var c: UInt32 = 0xFFFF_FFFF
    for byte in bytes { c = crcTable[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
    return c ^ 0xFFFF_FFFF
}

func adler32(_ bytes: [UInt8]) -> UInt32 {
    var a: UInt32 = 1
    var b: UInt32 = 0
    for byte in bytes {
        a = (a + UInt32(byte)) % 65521
        b = (b + a) % 65521
    }
    return (b << 16) | a
}

func bigEndian(_ value: UInt32) -> [UInt8] {
    [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
}

func chunk(_ type: String, _ data: [UInt8]) -> [UInt8] {
    let body = Array(type.utf8) + data
    return bigEndian(UInt32(data.count)) + body + bigEndian(crc32(body))
}

/// A zlib stream, by way of `gzip` and a change of container.
///
/// gzip is 10 bytes of header, the deflate stream, then a CRC-32 and a length; zlib is two
/// bytes of header, the same deflate stream, then an Adler-32. Nothing is recompressed —
/// the deflate bytes are carried across untouched, which is why the output matches what
/// zlib itself produces at level 9 rather than merely being valid.
///
/// The second header byte is `0xDA` rather than `0x9C`: it is the compression-level hint,
/// which gzip does not record, and `0xDA` is what zlib itself writes at level 9.
func zlibStream(_ raw: [UInt8]) throws -> [UInt8] {
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent("decoy-assets-\(raw.count).bin")
    try Data(raw).write(to: temporary)
    defer { try? FileManager.default.removeItem(at: temporary) }

    // `-n` so no modification time or filename lands in the header, which would make the
    // offsets wrong and the build non-reproducible.
    let result = try Shell.run("gzip", ["-9", "-n", "-c", temporary.path], captureOutput: true)
    guard result.status == 0, result.output.count > 18 else {
        throw AssetFailure.compressionFailed(result.stderr)
    }
    let deflate = [UInt8](result.output.dropFirst(10).dropLast(8))
    return [0x78, 0xDA] + deflate + bigEndian(adler32(raw))
}

enum AssetFailure: Error, CustomStringConvertible {
    case compressionFailed(String)
    case contrast([String])

    var description: String {
        switch self {
        case .compressionFailed(let detail):
            return "gzip could not compress the image data: \(detail)"
        case .contrast(let problems):
            return "contrast below AA:\n  " + problems.joined(separator: "\n  ")
        }
    }
}

/// Minimal RGBA PNG: one IHDR, one IDAT of unfiltered scanlines, one IEND.
func encodePNG(size: Int, rgba: [UInt8]) throws -> [UInt8] {
    let stride = size * 4 + 1
    var raw = [UInt8](repeating: 0, count: stride * size)
    for y in 0..<size {
        raw[y * stride] = 0  // filter type 0, none
        let source = y * size * 4
        raw.replaceSubrange(
            (y * stride + 1)..<(y * stride + 1 + size * 4),
            with: rgba[source..<(source + size * 4)])
    }

    var ihdr = bigEndian(UInt32(size)) + bigEndian(UInt32(size))
    ihdr += [8, 6, 0, 0, 0]  // 8-bit RGBA

    return [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        + chunk("IHDR", ihdr)
        + chunk("IDAT", try zlibStream(raw))
        + chunk("IEND", [])
}

// MARK: - The wordmark

let X = 100.0  // x-height
let SW = 0.185 * X  // stroke weight
let ASC = 0.42 * X  // ascender above x-height (the `d` stem)
let DESC = 0.44 * X  // descender below baseline (the `y` tail)
let GAP = 0.13 * X  // sidebearing; round letters carry their own air
let RADIUS = X / 2  // bowl radius

func at(_ cx: Double, _ cy: Double, _ r: Double, _ deg: Double) -> (x: Double, y: Double) {
    let t = deg * Double.pi / 180
    return (cx + r * cos(t), cy - r * sin(t))  // y grows downward
}

/// Outer circle plus a counter wound the other way, so nonzero fill leaves it hollow while
/// still unioning cleanly with any stroke laid across it. Even-odd would XOR the overlap and
/// punch holes where the `e` bar and the `d` stem cross their bowls.
func ring(_ cx: Double, _ cy: Double, _ ro: Double, _ ri: Double) -> String {
    "M\(f(cx - ro)),\(f(cy))A\(f(ro)),\(f(ro)) 0 1 0 \(f(cx + ro)),\(f(cy))"
        + "A\(f(ro)),\(f(ro)) 0 1 0 \(f(cx - ro)),\(f(cy))Z"
        + "M\(f(cx - ri)),\(f(cy))A\(f(ri)),\(f(ri)) 0 1 1 \(f(cx + ri)),\(f(cy))"
        + "A\(f(ri)),\(f(ri)) 0 1 1 \(f(cx - ri)),\(f(cy))Z"
}

/// Open ring segment from a0 to a1, counterclockwise on screen.
func arcSeg(_ cx: Double, _ cy: Double, _ ro: Double, _ ri: Double, _ a0: Double, _ a1: Double)
    -> String
{
    let large = (a1 - a0 + 360).truncatingRemainder(dividingBy: 360) > 180 ? 1 : 0
    let o0 = at(cx, cy, ro, a0)
    let o1 = at(cx, cy, ro, a1)
    let i0 = at(cx, cy, ri, a0)
    let i1 = at(cx, cy, ri, a1)
    return "M\(f(o0.x)),\(f(o0.y))A\(f(ro)),\(f(ro)) 0 \(large) 0 \(f(o1.x)),\(f(o1.y))"
        + "L\(f(i1.x)),\(f(i1.y))A\(f(ri)),\(f(ri)) 0 \(large) 1 \(f(i0.x)),\(f(i0.y))Z"
}

/// A thick straight stroke between two points.
func stroke(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ w: Double) -> String {
    let dx = x1 - x0
    let dy = y1 - y0
    let n = (dx * dx + dy * dy).squareRoot()
    let px = (-dy / n) * (w / 2)
    let py = (dx / n) * (w / 2)
    return "M\(f(x0 + px)),\(f(y0 + py))L\(f(x1 + px)),\(f(y1 + py))"
        + "L\(f(x1 - px)),\(f(y1 - py))L\(f(x0 - px)),\(f(y0 - py))Z"
}

/// The path and the advance. The baseline sits at y = X.
func letter(_ ch: Character, _ x: Double) -> (path: String, advance: Double) {
    let ro = RADIUS
    let ri = RADIUS - SW
    let cy = X - RADIUS

    switch ch {
    case "o":
        return (ring(x + RADIUS, cy, ro, ri), X)
    case "c":
        return (arcSeg(x + RADIUS, cy, ro, ri, 52, -52), X)
    case "e":
        // The stroke runs from the bar's right terminal anticlockwise round to the
        // lower-right aperture; the bar closes the counter and ends the stroke.
        return (
            arcSeg(x + RADIUS, cy, ro, ri, 0, -48)
                + stroke(x + RADIUS - ro, cy, x + RADIUS + ro * 0.97, cy, SW), X
        )
    case "d":
        return (
            ring(x + RADIUS, cy, ro, ri) + stroke(x + X - SW / 2, -ASC, x + X - SW / 2, X, SW), X
        )
    case "y":
        // The right stroke runs unbroken into the descender; the left arm meets it. The
        // junction is solved for rather than eyeballed — a plausible-looking point left the
        // two strokes ten units apart and the letter came out visibly broken.
        let topR = x + X - SW * 0.5
        let tipX = x + X * 0.26
        let tipY = X + DESC
        let jy = X * 0.6
        let jx = topR + (jy / tipY) * (tipX - topR)
        return (
            stroke(topR, 0, tipX, tipY, SW) + stroke(x + SW * 0.5, 0, jx, jy, SW), X * 0.94
        )
    default:
        fatalError("no glyph for \(ch)")
    }
}

/// Optical kerning: `o` and `y` both carry their mass away from the join, so the metric gap
/// reads far wider than it measures.
let kerning: [String: Double] = ["oy": -0.06 * X, "ec": -0.02 * X, "co": -0.02 * X]

struct Wordmark {
    let body: String
    let width: Double
    let top: Double
    let bottom: Double
}

func wordmark(_ colour: String) -> Wordmark {
    let word = Array("decoy")
    var paths: [String] = []
    var x = 0.0
    for index in word.indices {
        let (path, advance) = letter(word[index], x)
        paths.append(path)
        let pair =
            index + 1 < word.count ? String(word[index...(index + 1)]) : String(word[index])
        x += advance + GAP + (kerning[pair] ?? 0)
    }
    return Wordmark(
        body: "<path d=\"\(paths.joined())\" fill=\"\(colour)\" fill-rule=\"nonzero\"/>",
        width: x - GAP, top: -ASC, bottom: X + DESC)
}

// MARK: - Lockups

let markHeight = 1.86  // mark height as a multiple of the wordmark x-height
let lockupGap = 0.34  // gap between mark and word, as a fraction of mark width

func lockup(_ colours: Colours, _ ink: String, stacked: Bool = false)
    -> (content: String, width: Double, height: Double)
{
    let shapes = markShapes(176, colours)
    let xs = shapes.flatMap { $0.points.map(\.x) }
    let ys = shapes.flatMap { $0.points.map(\.y) }
    let mx0 = xs.min() ?? 0
    let my0 = ys.min() ?? 0
    let mw = (xs.max() ?? 0) - mx0
    let mh = (ys.max() ?? 0) - my0
    let s = (markHeight * X) / mh
    let sw = mw * s
    let sh = mh * s

    let word = wordmark(ink)
    let wh = word.bottom - word.top
    let totalW: Double
    let totalH: Double
    let mx: Double
    let my: Double
    let wx: Double
    let wy: Double

    if stacked {
        let gap = 0.17 * sh
        totalW = max(sw, word.width)
        totalH = sh + gap + wh
        mx = (totalW - sw) / 2
        my = 0
        wx = (totalW - word.width) / 2
        wy = sh + gap - word.top
    } else {
        let gap = lockupGap * sw
        totalW = sw + gap + word.width
        totalH = max(sh, wh)
        mx = 0
        my = (totalH - sh) / 2
        // Optically centred on the x-height band rather than the full ascender-to-descender
        // box: the `d` stem and the `y` tail are thin and carry little weight.
        wx = sw + gap
        wy = (totalH - X) / 2
    }

    let marks = shapes.map { shape in
        let points = shape.points
            .map { "\(f(($0.x - mx0) * s + mx)),\(f(($0.y - my0) * s + my))" }
            .joined(separator: " ")
        return "<polygon points=\"\(points)\" fill=\"\(shape.fill)\"/>"
    }.joined()

    return (
        marks + "<g transform=\"translate(\(f(wx)),\(f(wy)))\">\(word.body)</g>",
        totalW, totalH
    )
}

func wrap(_ content: String, _ w: Double, _ h: Double, padRatio: Double = 0.08, extra: String = "")
    -> String
{
    let pad = max(w, h) * padRatio
    return "<svg xmlns=\"http://www.w3.org/2000/svg\" \(extra)viewBox=\"\(f(-pad)) \(f(-pad)) "
        + "\(f(w + 2 * pad)) \(f(h + 2 * pad))\">\(content)</svg>\n"
}

// MARK: - Contrast self-check

func luminance(_ hex: String) -> Double {
    let (r, g, b) = hexToRGB(hex)
    let channels = [r, g, b].map { value -> Double in
        let c = Double(value) / 255
        return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
}

func contrast(_ a: String, _ b: String) -> Double {
    let (la, lb) = (luminance(a), luminance(b))
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

/// Fails the build when a text token drops below WCAG AA against its own ground.
///
/// Here rather than in a document because a palette written down is a palette that drifts.
/// The mark's own colours are exempt: they are graphic fills, and `#328191` measures
/// 4.21:1, which is why a darkened sibling carries links and body text.
func checkContrast() throws {
    var problems: [String] = []
    for (name, tokens) in [("light", Palette.textLight), ("dark", Palette.textDark)] {
        let lookup = Dictionary(uniqueKeysWithValues: tokens)
        for key in ["ink", "muted", "faint", "accent", "caution"] {
            guard let colour = lookup[key], let paper = lookup["paper"] else { continue }
            let ratio = contrast(colour, paper)
            if ratio < 4.5 {
                problems.append("\(name).\(key) \(colour) = \(String(format: "%.2f", ratio)):1")
            }
        }
    }
    guard problems.isEmpty else { throw AssetFailure.contrast(problems) }
    print("  contrast        all text tokens >= 4.5:1")
}

// MARK: - Build

/// The icon keeps the straw. That was tested rather than assumed, and the assumption was
/// wrong: a strawless reduction reads as a shelf at 16px, because what survives is not the
/// wedges but the amber mass beneath the brim — the mark's only colour contrast, and the
/// thing that makes it findable in a tab strip. Shorter, fatter wedges hold the grid.
let iconOptions: MarkOptions = {
    var options = MarkOptions()
    options.strawLen = 0.36
    options.baseHW = 0.068
    options.tipHW = 0.046
    return options
}()

let variants:
    [(name: String, colours: Colours, options: MarkOptions, pad: Double, sizes: [Int])] = [
        ("logo", Palette.mark, MarkOptions(), 0.10, [512, 1024]),
        ("logo-dark", Palette.markDark, MarkOptions(), 0.10, [512, 1024]),
        ("icon", Palette.mark, iconOptions, 0.05, [16, 32, 48, 180, 512]),
        ("icon-dark", Palette.markDark, iconOptions, 0.05, [16, 32, 180, 512]),
    ]

let here = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Assets")

func write(_ name: String, _ data: [UInt8]) throws {
    try Data(data).write(to: here.appendingPathComponent(name))
}

func padded(_ name: String) -> String {
    name.count >= 16 ? name : name + String(repeating: " ", count: 16 - name.count)
}

do {
    try FileManager.default.createDirectory(at: here, withIntermediateDirectories: true)

    for variant in variants {
        let shapes = markShapes(176, variant.colours, variant.options)
        try write("\(variant.name).svg", Array(markSVG(shapes, variant.pad).utf8))
        for size in variant.sizes {
            let rgba = rasterise(shapes, size: size, padRatio: variant.pad)
            try write("\(variant.name)-\(size).png", try encodePNG(size: size, rgba: rgba))
        }
        print("  \(padded(variant.name))svg + \(variant.sizes.count) png")
    }

    // Lockups and the wordmark ship as SVG only. They are set as text-like artwork with
    // arcs, and rasterising a logo is a downgrade unless a specific pixel size is demanded
    // — which is true of favicons and of nothing else here.
    for (name, colours, ink, stacked) in [
        ("lockup", Palette.mark, Palette.mark.ink, false),
        ("lockup-dark", Palette.markDark, Palette.markDark.ink, false),
        ("lockup-stacked", Palette.mark, Palette.mark.ink, true),
        ("lockup-stacked-dark", Palette.markDark, Palette.markDark.ink, true),
    ] {
        let built = lockup(colours, ink, stacked: stacked)
        try write(
            "\(name).svg", Array(wrap(built.content, built.width, built.height).utf8))
        print("  \(padded(name))svg  \(Int(built.width.rounded(.toNearestOrAwayFromZero))) wide")
    }

    for (name, ink) in [("wordmark", Palette.mark.ink), ("wordmark-dark", Palette.markDark.ink)] {
        let w = wordmark(ink)
        let content = "<g transform=\"translate(0,\(f(-w.top)))\">\(w.body)</g>"
        try write("\(name).svg", Array(wrap(content, w.width, w.bottom - w.top).utf8))
        print("  \(padded(name))svg  \(Int(w.width.rounded(.toNearestOrAwayFromZero))) wide")
    }

    try checkContrast()
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
