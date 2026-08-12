#!/usr/bin/env python3
"""Builds Decoy's logo assets from computed geometry.

One geometry function feeds both writers, so the SVG and the PNGs cannot drift.
Every proportion is a ratio of the brim width, so the mark is rebalanced by
changing a number rather than by nudging shapes, and the straw fan is generated
from mirrored angles -- the part a raster original could never get exactly right.

    python3 build-logo.py

PNGs are drawn here rather than via a thumbnailer because thumbnailers composite
onto white, which bakes a background into what has to be a transparent favicon.
"""
import math

TEAL, CREAM, AMBER = "#328191", "#F2EDE1", "#E0A029"
# Lifted for dark grounds: #328191 sits too close to #0F1216 to hold an edge.
TEAL_D, CREAM_D = "#5AAEC0", "#EDE7DA"


def geometry(W, teal, cream, amber, *, crown_h=.27, band_h=.11, brim_h=.13,
             top_w=.48, mid_w=.53, base_w=.57, straw_len=.42, root_spread=.15,
             base_hw=.058, tip_hw=.038, angles=(-48, -24, 0, 24, 48)):
    """Returns [(polygon points, colour)] with the origin at the crown's top centre."""
    ch, bh, mh, sl = crown_h*W, band_h*W, brim_h*W, straw_len*W
    y1, y2, y3 = ch, ch+bh, ch+bh+mh
    out, n = [], len(angles)
    for i, deg in enumerate(angles):                    # straw first, so the brim covers the joins
        t = math.radians(deg)
        rx = (i-(n-1)/2)/((n-1)/2) * root_spread*W
        ry = y3 - mh*.6                                 # rooted inside the brim
        tx, ty = rx + sl*math.sin(t), ry + sl*math.cos(t)
        px, py = math.cos(t), -math.sin(t)              # perpendicular to the wedge axis
        b, k = base_hw*W, tip_hw*W
        out.append(([(rx+b*px, ry+b*py), (tx+k*px, ty+k*py),
                     (tx-k*px, ty-k*py), (rx-b*px, ry-b*py)], amber))
    tw, mw, bw = top_w*W/2, mid_w*W/2, base_w*W/2
    out.append(([(-tw, 0), (tw, 0), (mw, y1), (-mw, y1)], teal))
    out.append(([(-mw, y1), (mw, y1), (bw, y2), (-bw, y2)], cream))
    out.append(([(-W/2, y2), (W/2, y2), (W/2, y3), (-W/2, y3)], teal))
    return out


def viewbox(shapes, pad_ratio):
    xs = [x for pts, _ in shapes for x, _ in pts]
    ys = [y for pts, _ in shapes for _, y in pts]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    w, h = x1-x0, y1-y0
    side = max(w, h) * (1 + 2*pad_ratio)
    return x0-(side-w)/2, y0-(side-h)/2, side


def to_svg(shapes, pad_ratio=.10):
    vx, vy, side = viewbox(shapes, pad_ratio)
    body = "".join(
        '<polygon points="%s" fill="%s"/>' %
        (" ".join(f"{x:.2f},{y:.2f}" for x, y in pts), col) for pts, col in shapes)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vx:.2f} {vy:.2f} '
            f'{side:.2f} {side:.2f}">{body}</svg>\n')


def to_png(shapes, path, size, pad_ratio=.10, ss=8):
    """Supersampled by `ss` then box-filtered down, which antialiases the straw's
    diagonal edges without a rendering dependency."""
    from PIL import Image, ImageDraw
    vx, vy, side = viewbox(shapes, pad_ratio)
    big = size * ss
    im = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for pts, col in shapes:
        d.polygon([((x-vx)/side*big, (y-vy)/side*big) for x, y in pts], fill=col)
    im.resize((size, size), Image.LANCZOS).save(path)


LIGHT = dict(teal=TEAL, cream=CREAM, amber=AMBER)
DARK = dict(teal=TEAL_D, cream=CREAM_D, amber=AMBER)
# The icon keeps the straw. That was tested rather than assumed, and the assumption
# was wrong: a strawless reduction reads as a shelf at 16px, because what survives
# is not the wedges but the amber mass beneath the brim -- the mark's only colour
# contrast. Shorter, fatter wedges and tighter padding hold up against the grid.
ICON = dict(straw_len=.36, base_hw=.068, tip_hw=.046)

VARIANTS = [
    ("logo",      LIGHT, {},   .10, (512, 1024)),
    ("logo-dark", DARK,  {},   .10, (512, 1024)),
    ("icon",      LIGHT, ICON, .05, (16, 32, 48, 180, 512)),
    ("icon-dark", DARK,  ICON, .05, (16, 32, 180, 512)),
]

if __name__ == "__main__":
    for name, palette, tweaks, pad, sizes in VARIANTS:
        shapes = geometry(176, **palette, **tweaks)
        open(f"{name}.svg", "w").write(to_svg(shapes, pad))
        for s in sizes:
            to_png(shapes, f"{name}-{s}.png", s, pad)
        print(f"  {name:10} svg + {len(sizes)} png")
