# Brand assets

A scarecrow's hat with straw beneath it, and no face — for a library that generates
people who do not exist. The absence under the brim is the idea.

Everything here is generated from computed geometry. **Do not edit the SVGs or PNGs by
hand**; change a ratio in the source and re-run it:

```
swift run decoy-assets
```

No dependencies, the same rule the rest of the toolchain follows. That is why the polygon
rasteriser and the PNG encoder are written out rather than being `sharp` or ImageMagick:
the point of a toolchain that takes no dependencies is not to take one for a favicon.

The one exception is compression. A PNG's image data is a zlib stream and Swift has no
portable zlib, so the deflate is done by `gzip` — already on every Unix machine, already
how the corpus build unpacks archives — and its output reframed from the gzip container
into the zlib one. Nothing is recompressed; the deflate bytes are carried across whole.

Nothing is drawn by hand. Every proportion is a ratio of the brim width, so the mark is
rebalanced by changing a number rather than by nudging shapes; the straw fan is
generated from mirrored angles; and the wordmark's letterforms are built from rings and
strokes on one monoline grid, which ties its weight to the mark's by construction.

## Files

| File | Use |
|---|---|
| `logo.svg`, `logo-{512,1024}.png` | README, docs header, social card |
| `icon.svg`, `icon-{16,32,48,180,512}.png` | favicon, app icon, package avatar |
| `lockup.svg` | mark and wordmark, horizontal — the primary logo |
| `lockup-stacked.svg` | the same, stacked, for square and narrow spaces |
| `wordmark.svg` | the word alone |
| `*-dark.svg` / `*-dark-*.png` | every one of the above, for dark grounds |

All PNGs are transparent RGBA — no background is baked in.

Lockups and the wordmark ship as **SVG only**. They are artwork set with arcs, and
rasterising a logo is a downgrade unless a specific pixel size is demanded — which is
true of favicons and of nothing else here.

## Palette

Brand colours are graphic fills and answer to the eye. Text colours are held to WCAG AA
and asserted by the build, which **fails** if a token drops below 4.5:1 against its own
ground. A palette written down in a document is a palette that drifts.

| | Light | Dark | Role |
|---|---|---|---|
| Mark teal | `#328191` | `#5AAEC0` | crown and brim |
| Mark cream | `#F2EDE1` | `#EDE7DA` | hat band |
| Mark amber | `#E0A029` | `#E0A029` | straw |
| Paper | `#F8F8F5` | `#0F1216` | page ground |
| Ink | `#12171E` | `#E9E7E2` | body text |
| Accent | `#2C7382` | `#5AAEC0` | links, emphasis |
| Caution | `#8F6114` | `#E0A029` | warnings |

Note that `#328191` is **not** the text accent. It measures 4.21:1 on paper, which
carries shapes and large headings but fails AA for body text, so links use a darkened
sibling. On dark grounds the mark's own lifted teal doubles as the accent, which is why
those two cells match.

The cream band nearly matches a paper background, so on light grounds it reads as a gap
between crown and brim rather than as a band, while on dark and coloured grounds it
reads as cream. That is deliberate and it looks right both ways, but it is not the same
mark. Making the band transparent would reduce it to two colours that behave identically
everywhere, if the inconsistency ever matters.

## Why the icon keeps the straw

The obvious reduction is to drop the straw for small sizes, since five tapered wedges
cannot survive a 16-pixel grid. That was tested, and it was wrong.

What survives at 16px is not the individual wedges but the **amber mass** beneath the
brim — the only colour contrast the mark has, and the thing that makes it findable in a
tab strip. Without it the icon is a teal block on a bar, which reads as a shelf. The
blur the reduction avoided cost less than the recognition it destroyed.

## Favicon markup

```html
<link rel="icon" href="/icon.svg" type="image/svg+xml">
<link rel="icon" href="/icon-32.png" sizes="32x32">
<link rel="apple-touch-icon" href="/icon-180.png">
```

Serving the SVG first lets modern browsers scale it themselves; the PNGs are the
fallback. `icon-180.png` is the iOS home-screen size, and iOS composites it onto black
on some versions — put it on `#F8F8F5` if it looks wrong on a home screen.

## Provenance

The concept and the colours came out of an Ideogram exploration. The shipped artwork is
this repository's own, constructed from geometry rather than traced, and carries the
same Apache-2.0 licence as the code. No font outlines are embedded: a system typeface
cannot be licensed into a distributed logo, and SVG `<text>` renders only where the font
is installed — which does not include GitHub. Hence the five drawn letters.
