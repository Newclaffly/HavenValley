"""Haven Valley art generator: isometric vector art drawn in code, rendered to PNG.

    python tools/art/iso_art.py            # everything
    python tools/art/iso_art.py tree_orange house_town_hall   # only some

Every asset is an SVG built from simple shapes (dark brown outline, flat colours with gradient
shading, soft shadows; light from the upper left). Chromium (Playwright) renders the SVGs at 2x
and the PNGs are trimmed and written to assets/art/. assets/art/manifest.json records, for each
image, the anchor pixel (where the object touches the ground) so Godot can place it exactly.

Conventions
  * Ground tile = 128 x 64 px in the game (art is drawn at 96 x 48 and scaled by 4/3).
  * Images are 2x resolution; Godot draws them at scale 0.5 (sharp when zoomed in).
  * Tile coordinates: +x = east (screen down-right), +y = south (screen down-left).
  * Buildings are built from the blueprint footprint (world_layout.json), 1 tile = 3.125 m.

Requires: Python 3 with Pillow, Node.js with the `playwright` package and its Chromium.
"""
import json
import math
import random
import subprocess
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "art"
WORK = ROOT / "tools" / "art" / "out"
RENDER_JS = ROOT / "tools" / "art" / "render_svg.js"
LAYOUT = ROOT / "resources" / "world" / "world_layout.json"
METRES_PER_TILE = 3.125
K = 4.0 / 3.0  # 96-px drawing tiles -> 128-px game tiles
INK = "#3d2a20"
SW = 2.6

# --- Drawing state (one asset at a time) --------------------------------------------------------

_out: list = []
_defs: list = []
_gid = [0]
_anchor = (0.0, 0.0)
rng = random.Random(1)


def begin(seed: int, ax: float, ay: float) -> None:
    global _anchor, rng
    _out.clear()
    _defs.clear()
    _anchor = (ax, ay)
    rng = random.Random(seed)
    _defs.append('<filter id="soft" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="5"/></filter>')
    _defs.append('<filter id="glow" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="8"/></filter>')


def end(width: int, height: int) -> str:
    ax, ay = _anchor
    body = "".join(_out)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">'
            f'<defs>{"".join(_defs)}</defs><g transform="translate({ax} {ay}) scale({K:.5f}) translate({-ax} {-ay})">{body}</g></svg>')


def iso(x, y, z=0.0):
    ax, ay = _anchor
    return (ax + (x - y) * 48.0, ay + (x + y) * 24.0 - z)


def pts(ps):
    return " ".join(f"{a:.1f},{b:.1f}" for a, b in ps)


def grad(c1, c2, x1=0, y1=0, x2=0, y2=1, stops=None):
    _gid[0] += 1
    gid = f"g{_gid[0]}"
    s = stops or [(0, c1), (1, c2)]
    _defs.append(f'<linearGradient id="{gid}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">'
                 + "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in s) + "</linearGradient>")
    return f"url(#{gid})"


def rgrad(c1, c2, cx=0.4, cy=0.35, r=0.75):
    _gid[0] += 1
    gid = f"r{_gid[0]}"
    _defs.append(f'<radialGradient id="{gid}" cx="{cx}" cy="{cy}" r="{r}"><stop offset="0" stop-color="{c1}"/>'
                 f'<stop offset="1" stop-color="{c2}"/></radialGradient>')
    return f"url(#{gid})"


def poly(ps, fill, stroke=INK, sw=SW, extra=""):
    _out.append(f'<polygon points="{pts(ps)}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" stroke-linejoin="round" {extra}/>')


def line(a, b, color=INK, sw=2, extra=""):
    _out.append(f'<line x1="{a[0]:.1f}" y1="{a[1]:.1f}" x2="{b[0]:.1f}" y2="{b[1]:.1f}" stroke="{color}" stroke-width="{sw}" stroke-linecap="round" {extra}/>')


def circle(c, r, fill, stroke=INK, sw=SW, extra=""):
    _out.append(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{r:.1f}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" {extra}/>')


def ellipse(c, rx, ry, fill, stroke=INK, sw=SW, extra=""):
    _out.append(f'<ellipse cx="{c[0]:.1f}" cy="{c[1]:.1f}" rx="{rx:.1f}" ry="{ry:.1f}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" {extra}/>')


def path(d, fill, stroke=INK, sw=SW, extra=""):
    _out.append(f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" stroke-linejoin="round" stroke-linecap="round" {extra}/>')


def shadow_poly(ps, opacity=0.28):
    _out.append(f'<polygon points="{pts(ps)}" fill="#1f3a14" opacity="{opacity}" filter="url(#soft)"/>')


def shadow_ellipse(c, rx, ry, opacity=0.3):
    _out.append(f'<ellipse cx="{c[0]:.1f}" cy="{c[1]:.1f}" rx="{rx:.1f}" ry="{ry:.1f}" fill="#1f3a14" opacity="{opacity}" filter="url(#soft)"/>')


def cast(x, y, z):
    """Where the shadow of (x, y, z) lands (light from the upper left)."""
    k = z / 48.0
    return iso(x + k * 0.55, y - k * 0.15)


def box(x0, x1, y0, y1, z0, z1, top, left, right, sw=SW):
    poly([iso(x0, y1, z0), iso(x1, y1, z0), iso(x1, y1, z1), iso(x0, y1, z1)], left, INK, sw)
    poly([iso(x1, y1, z0), iso(x1, y0, z0), iso(x1, y0, z1), iso(x1, y1, z1)], right, INK, sw)
    poly([iso(x0, y0, z1), iso(x1, y0, z1), iso(x1, y1, z1), iso(x0, y1, z1)], top, INK, sw)


# --- Nature ---------------------------------------------------------------------------------------

def tree_fruit(fruit: str, size: float = 1.0):
    s = size
    base = iso(0, 0)
    sh = cast(0, 0, 100 * s)
    shadow_ellipse(((base[0] + sh[0]) / 2 + 10, (base[1] + sh[1]) / 2 + 6), 58 * s, 22 * s, 0.32)
    tw = 11 * s
    path(f"M{base[0]-tw-4:.1f},{base[1]+2:.1f} q4,-8 {tw:.1f},-14 L{base[0]-tw*0.55:.1f},{base[1]-74*s:.1f} "
         f"L{base[0]+tw*0.55:.1f},{base[1]-74*s:.1f} L{base[0]+tw*0.9:.1f},{base[1]-12:.1f} q4,6 {tw:.1f},14 z",
         grad("#9c6a3e", "#6e4426", 0, 0, 1, 0))
    for k in range(3):
        path(f"M{base[0]-3+k*3:.1f},{base[1]-12-k*14:.1f} q2,-8 0,-14", "none", "#5a3820", 1.4)
    blobs = [(-28, -96, 34), (26, -100, 36), (0, -130, 40), (-8, -86, 30), (32, -78, 26), (-36, -72, 24), (8, -74, 26)]
    for dx, dy, r in blobs:
        circle((base[0] + dx * s, base[1] + dy * s), r * s + 2.8, INK, "none", 0)
    for dx, dy, r in blobs:
        circle((base[0] + dx * s, base[1] + dy * s), r * s, "#3f7f36", "none", 0)
    for dx, dy, r in blobs:
        circle((base[0] + (dx - 5) * s, base[1] + (dy - 7) * s), r * s * 0.82, "#5fa04a", "none", 0)
    for dx, dy, r in blobs[:4]:
        circle((base[0] + (dx - 10) * s, base[1] + (dy - 13) * s), r * s * 0.5, "#86c25f", "none", 0)
        circle((base[0] + (dx - 14) * s, base[1] + (dy - 17) * s), r * s * 0.22, "#b4e07f", "none", 0)
    for _ in range(18):
        dx, dy = rng.uniform(-50, 50), rng.uniform(-150, -66)
        path(f"M{base[0]+dx*s:.1f},{base[1]+dy*s:.1f} q3,-4 6,0 q-3,3 -6,0", "#2f6a2c", "none", 0, 'opacity="0.6"')
    if fruit:
        for dx, dy in [(-30, -102), (14, -124), (36, -90), (-10, -78), (8, -104), (-40, -82)]:
            p = (base[0] + dx * s, base[1] + dy * s)
            circle(p, 6.5 * s, rgrad("#ffe0a8", fruit, 0.35, 0.3), INK, 1.8)
            circle((p[0] - 2, p[1] - 2), 1.6 * s, "#ffffff", "none", 0, 'opacity="0.8"')


def tree_pine(size: float = 1.0):
    s = size
    base = iso(0, 0)
    sh = cast(0, 0, 120 * s)
    shadow_ellipse(((base[0] + sh[0]) / 2 + 8, (base[1] + sh[1]) / 2 + 6), 44 * s, 18 * s, 0.32)
    path(f"M{base[0]-9*s:.1f},{base[1]+1:.1f} L{base[0]-6*s:.1f},{base[1]-40*s:.1f} L{base[0]+6*s:.1f},{base[1]-40*s:.1f} L{base[0]+9*s:.1f},{base[1]+1:.1f} z",
         grad("#8a5a36", "#5e3a20", 0, 0, 1, 0))
    tiers = [(-30, 46, 52), (-68, 38, 48), (-102, 29, 42), (-132, 19, 36)]
    for i, (y0, half, height) in enumerate(tiers):
        yb = base[1] + y0 * s
        hw = half * s
        top = yb - height * s
        d = (f"M{base[0]-hw:.1f},{yb:.1f} q{hw*0.5:.1f},{8*s:.1f} {hw:.1f},{2*s:.1f} q{hw*0.5:.1f},{6*s:.1f} {hw:.1f},{-2*s:.1f} "
             f"L{base[0]+hw*0.15:.1f},{top:.1f} q{-hw*0.15:.1f},{-4*s:.1f} {-hw*0.3:.1f},0 z")
        path(d, grad("#4e8f4a", "#2b5f34", 0, 0, 1, 0))
        path(f"M{base[0]-hw*0.8:.1f},{yb-3*s:.1f} L{base[0]-hw*0.05:.1f},{top+6*s:.1f}", "none", "#7cbf5a", 3 * s, 'opacity="0.7"')
        for k in range(3):
            xx = base[0] - hw * 0.6 + k * hw * 0.5
            path(f"M{xx:.1f},{yb-2*s:.1f} q3,-6 7,-3", "none", "#22502b", 1.4)
    circle((base[0] + 2 * s, base[1] - 166 * s), 3 * s, "#f6e7a8", INK, 1.2)


def bush(berries: str = "#ffffff", colors=("#4f8f3f", "#6aae4f", "#94d06a")):
    p = iso(0, 0)
    shadow_ellipse((p[0] + 10, p[1] + 3), 26, 8, 0.3)
    bl = [(-14, -12, 15), (12, -12, 14), (0, -22, 16)]
    for dx, dy, r in bl:
        circle((p[0] + dx, p[1] + dy), r + 2.8, INK, "none", 0)
    for dx, dy, r in bl:
        circle((p[0] + dx, p[1] + dy), r, colors[0], "none", 0)
    for dx, dy, r in bl:
        circle((p[0] + dx - 3, p[1] + dy - 4), r * 0.75, colors[1], "none", 0)
        circle((p[0] + dx - 6, p[1] + dy - 7), r * 0.3, colors[2], "none", 0)
    if berries:
        for k in range(5):
            circle((p[0] - 16 + k * 8, p[1] - 16 - (k % 2) * 9), 3, berries, INK, 1.1)


def rock(s: float = 1.0, moss: bool = False):
    p = iso(0, 0)
    shadow_ellipse((p[0] + 10 * s, p[1] + 4), 28 * s, 9 * s, 0.32)
    path(f"M{p[0]-26*s:.1f},{p[1]:.1f} q-2,-18 12,-26 q14,-10 28,-2 q14,8 12,28 z", rgrad("#ece6da", "#9a9184", 0.35, 0.25), INK, 2.4)
    path(f"M{p[0]-10*s:.1f},{p[1]-22*s:.1f} q8,-6 16,-2", "none", "#ffffff", 2, 'opacity="0.8"')
    path(f"M{p[0]+2*s:.1f},{p[1]-4:.1f} q6,-8 14,-6", "none", "#7d756a", 1.4)
    if moss:
        ellipse((p[0] - 10 * s, p[1] - 18 * s), 11 * s, 5 * s, "#8fbf63", INK, 1.2)


def flower_patch(colors):
    for i in range(9):
        p = iso(rng.uniform(-0.35, 0.35), rng.uniform(-0.35, 0.35))
        col = rng.choice(colors)
        h = rng.uniform(9, 15)
        path(f"M{p[0]:.1f},{p[1]:.1f} q1,{-h/2:.1f} 0,{-h:.1f}", "none", "#4e8a33", 1.8)
        path(f"M{p[0]:.1f},{p[1]-3:.1f} q-6,-3 -7,-7 q5,1 7,7", "#6fb04a", "none", 0)
        for k in range(5):
            a_ = k * 1.2566 + 0.3
            circle((p[0] + math.cos(a_) * 4.2, p[1] - h + math.sin(a_) * 3.6), 3.4, col, INK, 1)
        circle((p[0], p[1] - h), 2.2, "#f2b93a", INK, 0.8)


# --- Props ----------------------------------------------------------------------------------------

def sign():
    p = iso(0, 0)
    shadow_ellipse((p[0] + 10, p[1] + 3), 14, 4, 0.3)
    line(p, (p[0], p[1] - 44), INK, 6.5)
    line(p, (p[0], p[1] - 44), "#a56f3f", 4)
    path(f"M{p[0]-24},{p[1]-66} l48,0 l0,24 l-48,0 z", grad("#f2d29a", "#d9ad6c"))
    line((p[0] - 20, p[1] - 47), (p[0] + 20, p[1] - 47), "#c4975a", 1.2)
    path(f"M{p[0]-13},{p[1]-54} l9,-6 l0,3.5 l15,0 l0,5 l-15,0 l0,3.5 z", "#6b4128", "none", 0)


def crates():
    x, y = -0.45, -0.2
    shadow_poly([iso(x, y + 0.45), iso(x + 0.9, y + 0.45), cast(x + 0.9, y, 50), cast(x, y + 0.45, 30)], 0.28)
    for dx, dy, dz in [(0, 0, 0), (0.46, 0, 0), (0.22, -0.02, 26)]:
        s = 0.42
        X, Y, Z = x + dx, y + dy, dz
        box(X, X + s, Y, Y + s, Z, Z + 25, grad("#f2c48a", "#dfa560"), grad("#e0a462", "#c4884a"), grad("#b97c42", "#94602f"), 2)
        line(iso(X, Y + s, Z + 12.5), iso(X + s, Y + s, Z + 12.5), "#8c5a2e", 1.6)
    p = iso(x + 0.43, y + 0.2, 53)
    for k in range(5):
        q = (p[0] - 12 + k * 6, p[1] - (k % 2) * 5)
        circle(q, 6.4, rgrad("#ffd38a", "#ef8a2a", 0.35, 0.3), INK, 1.6)


def lamp():
    p = iso(0, 0)
    shadow_ellipse((p[0] + 14, p[1] + 3), 14, 4, 0.3)
    line(p, (p[0], p[1] - 96), INK, 7)
    line(p, (p[0], p[1] - 96), "#5c5850", 4)
    line((p[0], p[1] - 94), (p[0] + 18, p[1] - 94), INK, 4)
    circle((p[0] + 18, p[1] - 80), 22, "#ffe08a", "none", 0, 'opacity="0.5" filter="url(#glow)"')
    ellipse((p[0] + 18, p[1] - 80), 8, 10, rgrad("#fff6c9", "#f2b93a"), INK, 2.2)


# --- Buildings ------------------------------------------------------------------------------------

BUILDING_STYLES = {
    # wall light, wall dark, roof light, roof dark, roof back, foundation
    "red": ("#d9674a", "#a3412c", "#ffd27a", "#e9a23c", "#d48a2c"),
    "cream": ("#f4e6c8", "#cdb98f", "#e8735a", "#c4513a", "#a9432f"),
    "blue": ("#9cc4e8", "#6f97be", "#7e8fa8", "#5b6b83", "#4c5a70"),
    "wood": ("#c99460", "#9c6a3e", "#8fbf63", "#5f9a3c", "#4e8231"),
    "stone": ("#d6cfc1", "#a39b8d", "#6f7d96", "#55617a", "#47526a"),
}


def house(w_tiles: float, d_tiles: float, wall_h: float, style: str, door_side: str = "left", chimney: bool = True,
          storeys: int = 1, tower: bool = False):
    wl, wd, rl, rd, rb = BUILDING_STYLES[style]
    x0, x1 = -w_tiles / 2, w_tiles / 2
    y0, y1 = -d_tiles / 2, d_tiles / 2
    h = wall_h
    ridge_along_x = w_tiles >= d_tiles
    rh = (d_tiles if ridge_along_x else w_tiles) * 22 + 20
    shadow_poly([iso(x1, y1), iso(x1, y0), cast(x1, y0, h + rh), cast(x1, y1, h + rh)], 0.3)
    shadow_poly([iso(x0, y1 + 0.05), iso(x1, y1 + 0.05), iso(x1 + 0.2, y1 + 0.35), iso(x0 + 0.1, y1 + 0.35)], 0.22)
    o = 0.3
    if ridge_along_x:
        ridge = (y0 + y1) / 2
        poly([iso(x0 - o, y0 - o, h - 8), iso(x1 + o, y0 - o, h - 8), iso(x1 + o, ridge, h + rh), iso(x0 - o, ridge, h + rh)], rb)
    else:
        ridge = (x0 + x1) / 2
        poly([iso(x0 - o, y0 - o, h - 8), iso(x0 - o, y1 + o, h - 8), iso(ridge, y1 + o, h + rh), iso(ridge, y0 - o, h + rh)], rb)
    # foundation then walls
    box(x0 - 0.06, x1 + 0.06, y0, y1 + 0.06, 0, 14, "#cfc8b8", grad("#d6cfc1", "#b5ad9e"), grad("#b0a898", "#8f8879"), 2.2)
    poly([iso(x0, y1, 14), iso(x1, y1, 14), iso(x1, y1, h), iso(x0, y1, h)], grad(wl, wd, 0, 0, 0, 1, [(0, wl), (1, _mix(wl, wd, 0.35))]))
    poly([iso(x1, y1, 14), iso(x1, y0, 14), iso(x1, y0, h), iso(x1, y1, h)], grad(wd, _mix(wd, "#000000", 0.2)))
    plank = _mix(wd, "#000000", 0.08)
    for i in range(1, int((x1 - x0) * 5)):
        xx = x0 + i / 5
        line(iso(xx, y1, 16), iso(xx, y1, h - 6), plank, 1.2, 'opacity="0.6"')
    for i in range(1, int((y1 - y0) * 5)):
        yy = y0 + i / 5
        line(iso(x1, yy, 16), iso(x1, yy, h - 6), _mix(wd, "#000000", 0.3), 1.2, 'opacity="0.6"')
    for (xa, ya) in [(x0, y1), (x1, y1), (x1, y0)]:
        line(iso(xa, ya, 14), iso(xa, ya, h), INK, 7)
        line(iso(xa, ya, 14), iso(xa, ya, h), "#7a4a2a", 4.5)
    if storeys > 1:
        line(iso(x0, y1, h * 0.52), iso(x1, y1, h * 0.52), INK, 6)
        line(iso(x0, y1, h * 0.52), iso(x1, y1, h * 0.52), "#7a4a2a", 3.5)
        line(iso(x1, y1, h * 0.52), iso(x1, y0, h * 0.52), INK, 6)
        line(iso(x1, y1, h * 0.52), iso(x1, y0, h * 0.52), "#5e3820", 3.5)
    poly([iso(x0, y1, h), iso(x1, y1, h), iso(x1, y1, h - 16), iso(x0, y1, h - 16)], "#2a120a", "none", 0, 'opacity="0.25"')
    # door and windows
    def door_left(cx):
        poly([iso(cx - 0.3, y1, 14), iso(cx + 0.3, y1, 14), iso(cx + 0.3, y1, 62), iso(cx - 0.3, y1, 62)], grad("#7a4a2c", "#5a321c"))
        for k in (-0.15, 0, 0.15):
            line(iso(cx + k, y1, 16), iso(cx + k, y1, 60), "#4a2814", 1.3)
        circle(iso(cx + 0.2, y1, 37), 2.6, "#f6d36b", INK, 1.2)
        box(cx - 0.42, cx + 0.42, y1, y1 + 0.35, 0, 8, "#e5dfd2", "#cfc8b8", "#b0a898", 1.8)
    def door_right(cy):
        poly([iso(x1, cy + 0.3, 14), iso(x1, cy - 0.3, 14), iso(x1, cy - 0.3, 62), iso(x1, cy + 0.3, 62)], grad("#6a3e24", "#4a2814"))
        circle(iso(x1, cy + 0.2, 37), 2.6, "#f6d36b", INK, 1.2)
        box(x1, x1 + 0.35, cy - 0.42, cy + 0.42, 0, 8, "#e5dfd2", "#cfc8b8", "#b0a898", 1.8)
    def window_left(wx, z0):
        poly([iso(wx - 0.08, y1, z0 - 4), iso(wx + 0.63, y1, z0 - 4), iso(wx + 0.63, y1, z0 + 30), iso(wx - 0.08, y1, z0 + 30)], "#f6ead2", INK, 2)
        poly([iso(wx, y1, z0), iso(wx + 0.55, y1, z0), iso(wx + 0.55, y1, z0 + 26), iso(wx, y1, z0 + 26)], grad("#d6f4fb", "#7fc3d6"))
        poly([iso(wx, y1, z0 + 26), iso(wx + 0.16, y1, z0 + 26), iso(wx + 0.1, y1, z0 + 4), iso(wx, y1, z0 + 2)], "#f7c9d4", INK, 1.2)
        poly([iso(wx + 0.55, y1, z0 + 26), iso(wx + 0.39, y1, z0 + 26), iso(wx + 0.45, y1, z0 + 4), iso(wx + 0.55, y1, z0 + 2)], "#f7c9d4", INK, 1.2)
        line(iso(wx + 0.22, y1, z0 + 22), iso(wx + 0.33, y1, z0 + 10), "#ffffff", 2.5, 'opacity="0.9"')
        box(wx - 0.1, wx + 0.65, y1, y1 + 0.18, z0 - 12, z0 - 4, "#a8764f", "#b98a5e", "#8c5f3d", 1.6)
        for k in range(5):
            circle(iso(wx - 0.04 + k * 0.17, y1 + 0.1, z0 - 1), 3.4, ["#f7a8c4", "#ffffff", "#f2c94c"][k % 3], INK, 1)
    def window_right(wy, z0):
        poly([iso(x1, wy + 0.4, z0 - 3), iso(x1, wy - 0.4, z0 - 3), iso(x1, wy - 0.4, z0 + 28), iso(x1, wy + 0.4, z0 + 28)], "#e8dcc2", INK, 2)
        poly([iso(x1, wy + 0.32, z0), iso(x1, wy - 0.32, z0), iso(x1, wy - 0.32, z0 + 25), iso(x1, wy + 0.32, z0 + 25)], grad("#9fd3df", "#5e9aab"))
        line(iso(x1, wy, z0), iso(x1, wy, z0 + 25), INK, 1.6)
    door_x = (x0 + x1) / 2
    door_y = (y0 + y1) / 2
    if door_side == "left":
        door_left(door_x)
    else:
        door_right(door_y)
    floors = [34] + ([34 + h * 0.5] if storeys > 1 else [])
    for z0 in floors:
        n = max(1, int((x1 - x0) / 1.4))
        for i in range(n):
            wx = x0 + (x1 - x0) * (i + 0.5) / n - 0.27
            if door_side == "left" and z0 == 34 and abs(wx + 0.27 - door_x) < 0.75:
                continue
            window_left(wx, z0)
        m = max(1, int((y1 - y0) / 1.6))
        for i in range(m):
            wy = y0 + (y1 - y0) * (i + 0.5) / m
            if door_side == "right" and z0 == 34 and abs(wy - door_y) < 0.8:
                continue
            window_right(wy, z0)
    # lantern
    lp = iso(door_x + 0.5, y1, 60) if door_side == "left" else iso(x1, door_y - 0.5, 60)
    circle(lp, 20, "#ffe08a", "none", 0, 'opacity="0.45" filter="url(#glow)"')
    ellipse(lp, 5, 7, rgrad("#fff6c9", "#f2b93a"), INK, 1.6)
    # roof
    if ridge_along_x:
        poly([iso(x1, y1, h), iso(x1, y0, h), iso(x1, ridge, h + rh - 6)], grad(wd, _mix(wd, "#000000", 0.2)))
        rows = max(3, int(rh / 12))
        for r in range(rows):
            t0, t1 = r / rows, (r + 1) / rows
            ya = y1 + o + (ridge - y1 - o) * t0
            yb = y1 + o + (ridge - y1 - o) * t1
            za = h - 10 + (rh + 10) * t0
            zb = h - 10 + (rh + 10) * t1
            front = []
            n = int((x1 - x0) * 5) + 2
            for k in range(n + 1):
                xx = x0 - o + (x1 - x0 + 2 * o) * k / n
                front.append(iso(xx, ya + (0.05 if k % 2 else 0), za - (3 if k % 2 else 0)))
            poly(front + [iso(x1 + o, yb, zb), iso(x0 - o, yb, zb)], grad(rl, rd, 0, 1, 0, 0) if r % 2 == 0 else grad(_mix(rl, rd, 0.15), rd, 0, 1, 0, 0), INK, 2)
        line(iso(x0 - o, ridge, h + rh + 2), iso(x1 + o, ridge, h + rh + 2), INK, 10)
        line(iso(x0 - o, ridge, h + rh + 2), iso(x1 + o, ridge, h + rh + 2), _mix(rd, "#000000", 0.15), 6.5)
        line(iso(x0 - o, ridge, h + rh + 4), iso(x1 + o, ridge, h + rh + 4), _mix(rl, "#ffffff", 0.4), 2, 'opacity="0.8"')
    else:
        # ridge along y: the visible slope faces +x (screen right); gable on the +y end (screen left)
        poly([iso(x0, y1, h), iso(x1, y1, h), iso(ridge, y1, h + rh - 6)], grad(wl, _mix(wl, wd, 0.4)))
        rows = max(3, int(rh / 12))
        for r in range(rows):
            t0, t1 = r / rows, (r + 1) / rows
            xa = x1 + o + (ridge - x1 - o) * t0
            xb = x1 + o + (ridge - x1 - o) * t1
            za = h - 10 + (rh + 10) * t0
            zb = h - 10 + (rh + 10) * t1
            front = []
            n = int((y1 - y0) * 5) + 2
            for k in range(n + 1):
                yy = y1 + o - (y1 - y0 + 2 * o) * k / n
                front.append(iso(xa + (0.05 if k % 2 else 0), yy, za - (3 if k % 2 else 0)))
            poly(front + [iso(xb, y0 - o, zb), iso(xb, y1 + o, zb)], grad(_mix(rl, rd, 0.3), rd, 0, 1, 0, 0) if r % 2 == 0 else grad(_mix(rl, rd, 0.45), rd, 0, 1, 0, 0), INK, 2)
        line(iso(ridge, y1 + o, h + rh + 2), iso(ridge, y0 - o, h + rh + 2), INK, 10)
        line(iso(ridge, y1 + o, h + rh + 2), iso(ridge, y0 - o, h + rh + 2), _mix(rd, "#000000", 0.15), 6.5)
    if tower:
        tx0, tx1, ty0, ty1 = -0.95, 0.95, y0 + 0.2, y0 + 2.1
        th = h + rh + 150
        box(tx0, tx1, ty0, ty1, h + 20, th, "#e9e0cc", grad(wl, _mix(wl, wd, 0.3)), grad(wd, _mix(wd, "#000000", 0.2)))
        cp = iso((tx0 + tx1) / 2, ty1, th - 50)
        circle(cp, 26, rgrad("#ffffff", "#e9e3d7"), INK, 2.6)
        line(cp, (cp[0], cp[1] - 18), INK, 3)
        line(cp, (cp[0] + 12, cp[1] + 4), INK, 3)
        for k in range(12):
            a_ = k * math.pi / 6
            circle((cp[0] + math.cos(a_) * 20, cp[1] + math.sin(a_) * 20), 1.5, INK, "none", 0)
        poly([iso(tx0 - 0.15, ty1 + 0.15, th), iso(tx1 + 0.15, ty1 + 0.15, th), iso((tx0 + tx1) / 2, (ty0 + ty1) / 2, th + 90)], grad(rl, rd), INK, 2.6)
        poly([iso(tx1 + 0.15, ty1 + 0.15, th), iso(tx1 + 0.15, ty0 - 0.15, th), iso((tx0 + tx1) / 2, (ty0 + ty1) / 2, th + 90)], grad(rd, _mix(rd, "#000000", 0.25)), INK, 2.6)
        circle(iso((tx0 + tx1) / 2, (ty0 + ty1) / 2, th + 96), 6, "#f6d36b", INK, 1.8)
    if chimney and not tower:
        cx_, cy_ = x0 + 0.5, y0 + 0.6
        box(cx_, cx_ + 0.38, cy_, cy_ + 0.38, h + 40, h + rh + 30, "#5c5850", grad("#b5ada0", "#8e877b"), grad("#857e72", "#615b52"), 2.2)
        p = iso(cx_ + 0.19, cy_ + 0.19, h + rh + 30)
        for dx, dy, r, op in [(4, -14, 9, 0.95), (14, -32, 12, 0.85), (28, -54, 15, 0.7)]:
            circle((p[0] + dx, p[1] + dy), r, "#ffffff", INK, 1.8, f'opacity="{op}"')


def _mix(a: str, b: str, t: float) -> str:
    ca = [int(a[i:i + 2], 16) for i in (1, 3, 5)]
    cb = [int(b[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(x + (y - x) * t):02x}" for x, y in zip(ca, cb))


# --- Player character -----------------------------------------------------------------------------

def villager(direction: str, phase: int):
    """Original character (straw hat, green shirt, beige overalls, satchel). phase 0..3 = walk cycle."""
    X, Y = iso(0, 0)
    step = (0, 1, 0, -1)[phase]
    bob = 2 if phase in (1, 3) else 0
    Y0 = Y - bob
    shadow_ellipse((X + 8, Y + 3), 22, 8, 0.38)
    mirror = direction == "right"
    if mirror:
        _out.append(f'<g transform="translate({2*X:.1f} 0) scale(-1 1)">')
    side = direction in ("left", "right")
    back = direction == "up"
    # legs
    pants_l, pants_r = grad("#e6d3a6", "#c9b487", 0, 0, 1, 0), grad("#d3bf92", "#b39f74", 0, 0, 1, 0)
    boot = grad("#7a4a2c", "#4a2814")
    if side:
        for k, (off, col) in enumerate(((-step * 5, pants_r), (step * 5, pants_l))):
            path(f"M{X-5+off},{Y0-28} L{X-5+off*1.2},{Y-7} L{X+3+off*1.2},{Y-7} L{X+3+off},{Y0-28} Z", col)
            path(f"M{X-9+off*1.2},{Y-6+0} q0,-7 6,-7 l6,0 l0,7 z", boot)
    else:
        for k, (dx, col) in enumerate(((-6, pants_l), (6, pants_r))):
            lift = (step if k == 0 else -step) * 3
            path(f"M{X+dx-4},{Y0-28} L{X+dx-4},{Y-7-max(0,lift)} L{X+dx+4},{Y-7-max(0,lift)} L{X+dx+4},{Y0-28} Z", col)
            path(f"M{X+dx-6},{Y-6-max(0,lift)} q0,-7 6,-7 l3,0 q3,0 3,7 z", boot)
    # torso
    Yb = Y0
    path(f"M{X-17},{Yb-60} q17,-8 34,0 l3,34 q-20,6 -40,0 z", grad("#8fd082", "#4f9a4a", 0, 0, 1, 0))
    if not back:
        if side:
            path(f"M{X-11},{Yb-46} l20,0 l2,22 q-12,4 -24,0 z", grad("#f2e2bd", "#cdb78a", 0, 0, 1, 0))
            line((X - 2, Yb - 46), (X - 4, Yb - 58), INK, 2.4)
        else:
            path(f"M{X-12},{Yb-46} l24,0 l2,22 q-14,4 -28,0 z", grad("#f2e2bd", "#cdb78a", 0, 0, 1, 0))
            path(f"M{X-5},{Yb-40} l10,0 l0,8 l-10,0 z", "#e2cfa2", INK, 1.4)
            line((X - 9, Yb - 46), (X - 12, Yb - 58), INK, 2.4)
            line((X + 9, Yb - 46), (X + 12, Yb - 58), INK, 2.4)
            circle((X - 7, Yb - 44), 2, "#f6d36b", INK, 1)
            circle((X + 7, Yb - 44), 2, "#f6d36b", INK, 1)
    else:
        path(f"M{X-12},{Yb-34} l24,0 l2,10 q-14,4 -28,0 z", grad("#f2e2bd", "#cdb78a", 0, 0, 1, 0))
        line((X - 9, Yb - 34), (X - 12, Yb - 58), INK, 2.4)
        line((X + 9, Yb - 34), (X + 12, Yb - 58), INK, 2.4)
    # satchel (on the right hip; seen from the side it is in front)
    if back:
        line((X + 14, Yb - 58), (X - 14, Yb - 32), "#7a4a2a", 4)
        path(f"M{X-23},{Yb-36} l15,0 l0,15 q-7.5,4 -15,0 z", grad("#d39a5e", "#9c6a3e"))
    elif side:
        path(f"M{X+2},{Yb-36} l14,0 l0,14 q-7,4 -14,0 z", grad("#d39a5e", "#9c6a3e"))
        line((X + 9, Yb - 36), (X + 6, Yb - 60), "#7a4a2a", 3.5)
    else:
        line((X - 14, Yb - 58), (X + 14, Yb - 32), "#7a4a2a", 4)
        path(f"M{X+8},{Yb-36} l15,0 l0,15 q-7.5,4 -15,0 z", grad("#d39a5e", "#9c6a3e"))
        path(f"M{X+8},{Yb-36} l15,0 l0,6 q-7.5,3 -15,0 z", "#b97c42", INK, 1.6)
    # arms swing opposite to the legs
    sw_ = step * 6
    if side:
        path(f"M{X-4},{Yb-56} q{-4-sw_},10 {-2-sw_},24 q5,2 8,-2 q0,-10 2,-18", grad("#8fd082", "#5fa856", 0, 0, 1, 0))
        circle((X - 3 - sw_, Yb - 31), 5, rgrad("#ffe1c4", "#eab894"), INK, 2)
    else:
        path(f"M{X-17},{Yb-56} q-9,10 -6,{24+sw_*0.3:.1f} q5,2 8,-2 q-1,-10 3,-18", grad("#8fd082", "#5fa856", 0, 0, 1, 0))
        circle((X - 21, Yb - 31 + sw_ * 0.3), 5, rgrad("#ffe1c4", "#eab894"), INK, 2)
        path(f"M{X+17},{Yb-56} q9,10 6,{24-sw_*0.3:.1f} q-5,2 -8,-2 q1,-10 -3,-18", grad("#6fb36a", "#4f9a4a", 0, 0, 1, 0))
        circle((X + 21, Yb - 31 - sw_ * 0.3), 5, rgrad("#ffe1c4", "#eab894"), INK, 2)
    # head
    Hy = Yb - 84
    circle((X, Hy), 24, rgrad("#ffe6cc", "#efbf9a", 0.38, 0.38, 0.8), INK, 2.8)
    hair_g = grad("#8e5a34", "#5e361c")
    if back:
        path(f"M{X-24},{Hy-2} q0,-24 24,-24 q24,0 24,24 q2,14 -6,22 q-18,6 -36,0 q-8,-8 -6,-22 z", hair_g)
        path(f"M{X-10},{Hy+16} q10,6 20,0", "none", "#4a2814", 1.6)
    elif side:
        # profile facing left: face on the left, hair over the top and back (right)
        path(f"M{X-23},{Hy-8} q4,-16 23,-16 q24,0 25,22 q1,14 -7,22 q-7,-9 -5,-20 q-9,-9 -36,-8 z", hair_g)
        path(f"M{X+6},{Hy+2} q8,-2 8,8 q-4,6 -9,2", "#efbf9a", INK, 1.6)  # ear
        path(f"M{X-13},{Hy+1} q4,-5 8,0", "none", INK, 2.4)  # closed happy eye
        ellipse((X - 9, Hy + 10), 5, 3, "#f59a9a", "none", 0, 'opacity="0.8"')
        path(f"M{X-23},{Hy+3} q-4,3 -1,6", "none", INK, 2)  # nose
        path(f"M{X-19},{Hy+13} q3,2.5 6,0", "none", INK, 1.8)
    else:
        path(f"M{X-24},{Hy-2} q2,-22 24,-22 q22,0 24,22 q-8,-8 -14,-6 q-6,-8 -12,-2 q-8,-6 -22,8 z", hair_g)
        path(f"M{X-23},{Hy} q-6,14 2,22 q3,-10 2,-20 z", "#6e4224")
        path(f"M{X+23},{Hy} q6,14 -2,22 q-3,-10 -2,-20 z", "#5e361c")
        path(f"M{X-12},{Hy+2} q4,-5 8,0", "none", INK, 2.4)
        path(f"M{X+4},{Hy+2} q4,-5 8,0", "none", INK, 2.4)
        ellipse((X - 14, Hy + 10), 5.5, 3.2, "#f59a9a", "none", 0, 'opacity="0.8"')
        ellipse((X + 14, Hy + 10), 5.5, 3.2, "#f59a9a", "none", 0, 'opacity="0.8"')
        path(f"M{X-4},{Hy+12} q4,4.5 8,0", "none", INK, 2.1)
    # straw hat
    ellipse((X, Hy - 20), 37, 10.5, grad("#ffe4a0", "#e0b45a"), INK, 2.8)
    path(f"M{X-18},{Hy-20} q2,-22 18,-22 q16,0 18,22 z", grad("#ffe9b0", "#dcae55", 0, 0, 1, 0))
    for k in range(-3, 4):
        path(f"M{X+k*5},{Hy-40} q{k*0.6},10 {k*1.1},18", "none", "#c99a45", 1, 'opacity="0.8"')
    path(f"M{X-17},{Hy-24} q17,5 34,0 l1,-5 q-18,5 -36,0 z", "#d9574a", INK, 1.8)
    if not back:
        path(f"M{X+14},{Hy-26} q8,-2 10,6 q-6,0 -10,-6", "#f2c94c", INK, 1.4)
    if mirror:
        _out.append("</g>")


# --- Asset list -----------------------------------------------------------------------------------

def buildings_from_layout() -> dict:
    layout = json.loads(LAYOUT.read_text(encoding="utf-8"))
    styles = {"civic": "cream", "shop": "red", "home": "wood", "farm": "red", "water": "wood"}
    heights = {"town_hall": 96, "barn": 92, "storage_delivery": 80, "restaurant": 104, "farmhouse": 100}
    areas = {"public_square", "marketplace", "community_garden", "small_park", "kitchen_garden", "pasture", "starter_field",
             "plot_a", "plot_b", "plot_c", "res_district", "mirror_lake"}
    found = {}
    for lm in layout["landmarks"]:
        fp = lm.get("footprint")
        if not fp or lm["id"] in areas:
            continue
        w, d = fp[0] / METRES_PER_TILE, fp[1] / METRES_PER_TILE
        if lm["id"] == "well":
            continue
        style = styles.get(lm.get("category", ""), "red")
        if lm["id"] == "greenhouse":
            style = "blue"
        if lm["id"] in ("blacksmith", "storage_delivery"):
            style = "stone"
        door = "right" if (lm.get("faces") or "S")[:1] == "E" else "left"
        h = heights.get(lm["id"], 80)
        found["house_" + lm["id"]] = dict(w=w, d=d, h=h, style=style, door=door, storeys=2 if h >= 100 else 1,
                                          tower=lm["id"] == "town_hall")
    for i, style in enumerate(("wood", "red", "cream")):
        found[f"house_village_{'abc'[i]}"] = dict(w=8 / METRES_PER_TILE, d=8 / METRES_PER_TILE, h=72, style=style, door="left", storeys=1, tower=False)
    return found


def assets() -> dict:
    """name -> (draw function, canvas width, canvas height, anchor x, anchor y)."""
    table = {
        "tree_orange": (lambda: tree_fruit("#ef8a2a"), 360, 420, 180, 380),
        "tree_apple": (lambda: tree_fruit("#e2453c", 1.05), 360, 420, 180, 380),
        "tree_lemon": (lambda: tree_fruit("#f2c94c", 0.95), 360, 420, 180, 380),
        "tree_oak": (lambda: tree_fruit("", 1.15), 380, 440, 190, 400),
        "tree_pine": (lambda: tree_pine(1.0), 300, 440, 150, 400),
        "tree_pine_tall": (lambda: tree_pine(1.25), 340, 520, 170, 480),
        "bush_flowers": (lambda: bush("#ffffff"), 200, 160, 100, 120),
        "bush_berries": (lambda: bush("#e85d7a", ("#467f38", "#5c9f48", "#88c45f")), 200, 160, 100, 120),
        "rock_small": (lambda: rock(0.8), 180, 140, 90, 110),
        "rock_large": (lambda: rock(1.4, True), 240, 180, 120, 140),
        "flowers_pink": (lambda: flower_patch(["#ffffff", "#f7a8c4"]), 200, 160, 100, 110),
        "flowers_yellow": (lambda: flower_patch(["#f2c94c", "#ffffff"]), 200, 160, 100, 110),
        "flowers_blue": (lambda: flower_patch(["#7aa8f0", "#ffffff"]), 200, 160, 100, 110),
        "sign": (sign, 160, 160, 80, 130),
        "crates": (crates, 220, 200, 110, 150),
        "lamp": (lamp, 160, 200, 60, 170),
    }
    for name, b in buildings_from_layout().items():
        # The house is symmetric left/right of its anchor; it rises by the wall, roof, chimney/tower.
        half_w = K * ((b["w"] + b["d"]) * 24 + 30)
        half_h = K * ((b["w"] + b["d"]) * 12 + 15)
        roof = (b["d"] if b["w"] >= b["d"] else b["w"]) * 22 + 20
        rise = K * (b["h"] + roof + (260 if b["tower"] else 110))
        width = int(2 * half_w + 80)
        ax = width // 2
        ay = int(half_h + rise + 30)
        table[name] = (lambda b=b: house(b["w"], b["d"], b["h"], b["style"], b["door"], storeys=b["storeys"], tower=b["tower"]),
                       width, int(ay + half_h + 30), ax, ay)
    return table


def render(jobs: list) -> None:
    WORK.mkdir(parents=True, exist_ok=True)
    (WORK / ".gdignore").write_text("")
    spec = WORK / "jobs.json"
    spec.write_text(json.dumps(jobs))
    subprocess.run(["node", str(RENDER_JS), str(spec)], check=True)


def trim(png: Path, anchor: tuple, dest: Path) -> dict:
    img = Image.open(png).convert("RGBA")
    box_ = img.getchannel("A").point(lambda a: 255 if a > 6 else 0).getbbox()
    if box_ is None:
        raise RuntimeError(f"{png} is empty")
    pad = 4
    l, t = max(0, box_[0] - pad), max(0, box_[1] - pad)
    r, b = min(img.width, box_[2] + pad), min(img.height, box_[3] + pad)
    img.crop((l, t, r, b)).save(dest, optimize=True)
    return {"anchor": [anchor[0] * 2 - l, anchor[1] * 2 - t], "size": [r - l, b - t]}


def main(only: list) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    WORK.mkdir(parents=True, exist_ok=True)
    manifest_path = OUT / "manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    table = assets()
    jobs = []
    for name, (draw, w, h, ax, ay) in table.items():
        if only and name not in only:
            continue
        w, h = w + 160, h + 70  # room for the soft shadows that fall to the lower right
        begin(sum(map(ord, name)), ax, ay)
        draw()
        (WORK / f"{name}.svg").write_text(end(w, h))
        jobs.append({"svg": str(WORK / f"{name}.svg"), "png": str(WORK / f"{name}.png"), "w": w, "h": h, "name": name, "anchor": [ax, ay]})
    # player walk sheet: 4 directions (columns) x 4 frames (rows), same frame size, no trimming
    frames = []
    if not only or "player_walk" in only:
        FW, FH, FAX, FAY = 130, 215, 65, 195
        for col, direction in enumerate(("down", "up", "left", "right")):
            for row in range(4):
                begin(7, FAX, FAY)
                villager(direction, row)
                n = f"player_{direction}_{row}"
                (WORK / f"{n}.svg").write_text(end(FW, FH))
                frames.append((col, row, n))
                jobs.append({"svg": str(WORK / f"{n}.svg"), "png": str(WORK / f"{n}.png"), "w": FW, "h": FH, "name": n, "anchor": [FAX, FAY]})
    WORK.mkdir(parents=True, exist_ok=True)
    render(jobs)
    for job in jobs:
        if job["name"].startswith("player_"):
            continue
        manifest[job["name"]] = trim(Path(job["png"]), tuple(job["anchor"]), OUT / f"{job['name']}.png")
    if frames:
        FW2, FH2 = 130 * 2, 215 * 2
        sheet = Image.new("RGBA", (FW2 * 4, FH2 * 4))
        for col, row, n in frames:
            sheet.paste(Image.open(WORK / f"{n}.png").convert("RGBA"), (col * FW2, row * FH2))
        sheet.save(OUT / "player_walk.png", optimize=True)
        manifest["player_walk"] = {"anchor": [65 * 2, 195 * 2], "size": [FW2, FH2], "frames": [4, 4]}
    manifest_path.write_text(json.dumps(manifest, indent=1, sort_keys=True))
    print(f"{len(jobs)} images rendered into {OUT}")


if __name__ == "__main__":
    main(sys.argv[1:])
