#!/usr/bin/env python3
"""Generate the Haven Valley heightmap and ground-type maps from the world blueprint.

Reads  resources/world/world_layout.json
Writes tools/terrain/out/heightmap_1025.f32   raw little-endian float32, 1025 x 1025, metres
       resources/world/terrain/control.png     RGBA: R dirt road, G tilled soil, B sand / river bed, A cobble
       resources/world/terrain/zones.png       RGB:  R forest floor, G meadow flowers, B mountain rock
       resources/world/terrain/heightmap_preview.png  shaded relief for checking by eye

Then run tools/terrain/build_terrain_resources.gd with Godot to turn the raw file into the
heightmap.res / heightmap.exr files the game and Terrain3D load.

Grid: sample (i, j) is world (x, z) = (-512 + i, -512 + j). 1 sample = 1 m. Godot axes: +X east, -Z north.
Requires Python 3.10+, numpy, scipy, Pillow.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
LAYOUT = ROOT / "resources/world/world_layout.json"
OUT_RAW = ROOT / "tools/terrain/out/heightmap_1025.f32"
OUT_DIR = ROOT / "resources/world/terrain"

N = 1025
ORIGIN = -512.0
SEED = 7

xs = ORIGIN + np.arange(N, dtype=np.float64)
X, Z = np.meshgrid(xs, xs)  # X[j, i] = x, Z[j, i] = z


# --- helpers ---------------------------------------------------------------------------------------

def smoothstep(e0, e1, v):
    t = np.clip((v - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def value_noise(scale: float, seed: int, octaves: int = 4) -> np.ndarray:
    """Smooth fractal noise in [-1, 1] at roughly `scale` metres per feature."""
    rng = np.random.default_rng(seed)
    total = np.zeros((N, N))
    amp, norm, s = 1.0, 0.0, scale
    for _ in range(octaves):
        cells = max(2, int(math.ceil(N / s)) + 2)
        grid = rng.uniform(-1.0, 1.0, (cells, cells))
        layer = ndimage.zoom(grid, N / (cells - 1), order=3, mode="nearest")[:N, :N]
        total += layer * amp
        norm += amp
        amp *= 0.5
        s *= 0.5
    return total / norm


def polyline_distance(points: np.ndarray, pad: float):
    """Distance from every sample to a polyline, plus distance along the line of the nearest point.
    Only samples inside the polyline's bounding box + pad are computed; others are +inf."""
    dist = np.full((N, N), np.inf)
    along = np.zeros((N, N))
    lo = points.min(axis=0) - pad
    hi = points.max(axis=0) + pad
    i0, i1 = int(max(0, lo[0] - ORIGIN)), int(min(N, hi[0] - ORIGIN + 1))
    j0, j1 = int(max(0, lo[1] - ORIGIN)), int(min(N, hi[1] - ORIGIN + 1))
    if i1 <= i0 or j1 <= j0:
        return dist, along
    px = X[j0:j1, i0:i1]
    pz = Z[j0:j1, i0:i1]
    best = np.full(px.shape, np.inf)
    best_s = np.zeros(px.shape)
    s_start = 0.0
    for a, b in zip(points[:-1], points[1:]):
        ab = b - a
        length = float(np.hypot(*ab))
        if length < 1e-6:
            continue
        t = np.clip(((px - a[0]) * ab[0] + (pz - a[1]) * ab[1]) / (length * length), 0.0, 1.0)
        d = np.hypot(px - (a[0] + t * ab[0]), pz - (a[1] + t * ab[1]))
        closer = d < best
        best = np.where(closer, d, best)
        best_s = np.where(closer, s_start + t * length, best_s)
        s_start += length
    dist[j0:j1, i0:i1] = best
    along[j0:j1, i0:i1] = best_s
    return dist, along


def cumulative(points: np.ndarray) -> np.ndarray:
    seg = np.hypot(*(np.diff(points, axis=0).T))
    return np.concatenate([[0.0], np.cumsum(seg)])


def sample(h: np.ndarray, x: float, z: float) -> float:
    fi = np.clip(x - ORIGIN, 0, N - 1.001)
    fj = np.clip(z - ORIGIN, 0, N - 1.001)
    i, j = int(fi), int(fj)
    tx, tz = fi - i, fj - j
    top = h[j, i] * (1 - tx) + h[j, i + 1] * tx
    bottom = h[j + 1, i] * (1 - tx) + h[j + 1, i + 1] * tx
    return float(top * (1 - tz) + bottom * tz)


# --- load blueprint --------------------------------------------------------------------------------

layout = json.loads(LAYOUT.read_text(encoding="utf-8"))
water = layout["water"]
landmarks = {lm["id"]: lm for lm in layout["landmarks"]}

# --- 1. natural base terrain -----------------------------------------------------------------------
# North-south profile along the valley (elevation plan, sheet D), without the creek and hill features.
profile_z = [-512, -500, -470, -450, -420, -400, -380, -340, -300, -260, -220, -170, -140, -90, 100, 150, 220, 300, 360, 400, 440, 470, 512]
profile_h = [150, 145, 125, 100, 75, 60, 52, 44, 36, 24, 18, 13, 11, 10, 10, 9, 8, 6, 5, 4, 4, 7, 12]

# Let the mountain foot wander north and south a little so the range is not a straight wall.
edge_wobble = value_noise(220, SEED + 1, 3) * 22.0
base = np.interp(Z + edge_wobble, profile_z, profile_h)

mountain = smoothstep(-235, -320, Z + edge_wobble)  # 0 in the valley, 1 in the range
ridges = 1.0 - np.abs(value_noise(90, SEED + 2, 5))  # ridged noise for peaks and gullies
base += mountain * (ridges - 0.5) * 34.0

# Westwood rises toward the west edge (12 m at the forest edge, ~40 m at the boundary).
west = np.clip((-262.0 - X) / 238.0, 0.0, 1.0) ** 1.15
base += west * 30.0

# East of the lake: hills that hide the east edge.
base += smoothstep(430, 512, X) * smoothstep(-300, -150, Z) * 10.0

# Windmill Hill and the southern rise.
base += 14.0 * np.exp(-(((X - 40) / 55.0) ** 2 + ((Z - 470) / 40.0) ** 2))

# Gentle rolling everywhere, stronger in meadows and forest, calm near the village.
rolling = value_noise(110, SEED + 3, 4)
calm = smoothstep(260, 120, np.hypot(X / 1.0, Z / 1.1))  # 1 near the village centre
base += rolling * (3.0 * (1 - calm) + 0.6 * calm)

# Lake basin: pull the surroundings of the lake down to shore level.
lake = water["lake"]
lcx, _, lcz = lake["center"]
lrx, lrz = lake["radii"]
lake_d = np.hypot((X - lcx) / lrx, (Z - lcz) / lrz)
shore_pull = smoothstep(1.9, 1.0, lake_d)
base = base * (1 - shore_pull) + np.minimum(base, 2.5 + rolling) * shore_pull

# Soft cap so ridge noise cannot push peaks far past the planned 150 m.
base = np.where(base > 140.0, 140.0 + (base - 140.0) * 0.35, base)

H = base.copy()
protected = np.zeros((N, N), dtype=bool)  # flat building ground that rivers and roads must not reshape
pads = []  # (x, z, radius, height) of every flat pad, used to pin road heights

# --- 2. flat building areas ------------------------------------------------------------------------

def flatten_mask(mask_inside: np.ndarray, dist_outside: np.ndarray, height, falloff: float):
    """Set terrain to `height` inside, blending back to the existing terrain over `falloff` metres."""
    global H
    w = np.where(mask_inside, 1.0, smoothstep(falloff, 0.0, dist_outside))
    H = H * (1 - w) + height * w
    protected[mask_inside] = True


# Farm Valley (Y 8): rectangle -245..-88 x 92..312.
fx0, fx1, fz0, fz1 = -245, -88, 92, 312
dx = np.maximum(np.maximum(fx0 - X, X - fx1), 0)
dz = np.maximum(np.maximum(fz0 - Z, Z - fz1), 0)
farm_dist = np.hypot(dx, dz)
flatten_mask(farm_dist == 0, farm_dist, 8.0, 32.0)

# Village plateau (Y 10), residential street raised to Y 11. The plateau stops 30 m short of the
# farm so the 2 m step between them becomes a gentle ramp.
vd = np.hypot(X / 150.0, Z / 170.0)
village_height = 10.0 + smoothstep(-88, -108, Z) * 1.0
village_core = (vd <= 0.92) & (farm_dist > 30.0)
w_village = np.where(village_core, 1.0, smoothstep(45.0, 0.0, (vd - 0.92) * 150.0) * smoothstep(0.0, 30.0, farm_dist))
w_village = np.where(farm_dist == 0, 0.0, w_village)
H = H * (1 - w_village) + village_height * w_village
protected |= village_core

# Landmark pads: every building and point of interest sits on flat ground at its blueprint height.
WATER_POINTS = {"mirror_lake", "river_spring", "creek_spring", "highfall", "willow_falls", "river_fishing",
                "outflow_cascade", "willow_isle", "fishing_pier", "lakeside_landing", "spawn"}
for lm in layout["landmarks"]:
    if lm["id"] in WATER_POINTS:
        continue
    x, y, z = lm["position"]
    fp = lm.get("footprint")
    if fp and lm["id"] != "res_district":
        r = max(fp) * 0.5 + 3.0
    else:
        r = 7.0
    d = np.hypot(X - x, Z - z)
    flatten_mask(d <= r, d - r, float(y), 18.0)
    pads.append((x, z, r, float(y)))

# --- 3. rivers, creek, lake ------------------------------------------------------------------------
water_mask = np.zeros((N, N), dtype=bool)  # true where roads must not flatten (channels, lake)
river_bed = np.zeros((N, N), dtype=bool)


def carve_channel(profile, half_width_fn, depth: float, bank_h_fn, bank_w: float, falloff: float):
    global H
    pts = np.array([[p[0], p[1]] for p in profile], dtype=np.float64)
    hs = np.array([p[2] for p in profile], dtype=np.float64)
    s_nodes = cumulative(pts)
    dist, along = polyline_distance(pts, pad=40.0 + bank_w + falloff)
    finite = np.isfinite(dist)
    ws = np.interp(along, s_nodes, hs)                 # water surface height at nearest point
    half_w = half_width_fn(along, s_nodes[-1])
    bank_h = bank_h_fn(along, s_nodes[-1], X, Z)
    channel = finite & (dist <= half_w)
    # Channel: parabolic bed from ws at the edge to ws - depth in the middle.
    bed = ws - depth * (1.0 - (dist / np.maximum(half_w, 0.1)) ** 2)
    # Bank: rises from the water edge to ws + bank_h over bank_w metres, then blends to terrain.
    rise = smoothstep(half_w, half_w + bank_w, dist)
    bank_top = ws + bank_h
    near_target = ws + bank_h * rise
    blend = smoothstep(half_w + bank_w, half_w + bank_w + falloff, dist)
    shaped = np.where(channel, bed, near_target * (1 - blend) + H * blend)
    # Outside the channel, never cut below the bank profile; never leave terrain under water.
    outside = finite & ~channel & ~protected & (dist <= half_w + bank_w + falloff)
    H = np.where(channel, bed, H)
    H = np.where(outside, shaped, H)
    water_mask[channel | (finite & (dist <= half_w + 2.0))] = True
    river_bed[channel] = True
    return dist, half_w


widths = water["widths"]


def river_half_width(along, total):
    # Narrow mountain stream above the mill, wide river below.
    return np.interp(along, [0, total * 0.45, total * 0.62, total], [widths["river_upper"] / 2, widths["river_upper"] / 2, widths["river_lower"] / 2, widths["river_lower"] / 2])


def river_bank(along, total, x, z):
    h = np.full(along.shape, 2.0)
    h = np.where(z > -140, 3.0, h)                      # stone-edged banks through the valley reach
    fish = np.hypot(x - 203, z + 62) < 14               # lowered bank at the fishing spot
    return np.where(fish, 0.8, h)


carve_channel(water["river_profile"], river_half_width, 1.6, river_bank, 5.0, 40.0)
carve_channel(water["creek_profile"], lambda a, t: np.full(a.shape, widths["creek"] / 2), 1.0,
              lambda a, t, x, z: np.full(a.shape, 1.5), 4.0, 28.0)
carve_channel(water["outflow_profile"], lambda a, t: np.full(a.shape, widths["outflow"] / 2), 1.2,
              lambda a, t, x, z: np.full(a.shape, 2.0), 4.0, 28.0)

# Mirror Lake: wading shelf (1.2 m) near shore, bowl to -8 in the middle.
inside = lake_d < 1.0
bed = np.where(lake_d > 0.93, -1.2 * smoothstep(1.0, 0.95, lake_d), -1.2 - 6.8 * smoothstep(0.92, 0.45, lake_d))
H = np.where(inside, np.minimum(H, bed), H)
shore = (lake_d >= 1.0) & (lake_d < 1.25)
H = np.where(shore, np.maximum(H, 0.5 + (lake_d - 1.0) * 8.0) * 1.0, H)
H = np.where(shore, np.minimum(H, 0.5 + (lake_d - 1.0) * 30.0), H)
water_mask |= lake_d < 1.02
river_bed |= inside

# Willow Isle
isl = water["island"]
idist = np.hypot(X - isl["center_xz"][0], Z - isl["center_xz"][1])
H = np.where(idist < isl["radius"], np.maximum(H, 1.6 - (idist / isl["radius"]) ** 2 * 2.8), H)

# --- 4. roads --------------------------------------------------------------------------------------
ROAD_CLASS = {
    "Village street": dict(grade=0.03, shoulder=1.0, falloff=4.0, smooth=20.0),
    "Main road": dict(grade=0.08, shoulder=1.5, falloff=8.0, smooth=50.0),
    "Lane": dict(grade=0.10, shoulder=0.5, falloff=6.0, smooth=40.0),
    "Footpath": dict(grade=0.14, shoulder=1.0, falloff=5.0, smooth=24.0),
    "Mountain trail": dict(grade=0.27, shoulder=1.2, falloff=5.0, smooth=16.0),
}
road_dirt = np.zeros((N, N))
road_core = np.zeros((N, N), dtype=bool)  # centre strips of roads already laid; later roads join them
road_cobble = np.zeros((N, N))
grade_report = []


def ellipse_points(c, r, n=96):
    a = np.linspace(0, 2 * np.pi, n + 1)
    return np.stack([c[0] + np.cos(a) * r[0], c[1] + np.sin(a) * r[1]], axis=1)


roads = [(r["id"], np.array(r["points_xz"], dtype=np.float64), r["width"], r["class"]) for r in layout["roads"]]
ring = layout["ring_road"]
roads.insert(0, ("R0", ellipse_points(ring["center_xz"], ring["radii"]), ring["width"], "Village street"))
loop = layout["lake_loop"]
roads.append(("P1", ellipse_points(loop["center_xz"], loop["radii"]), loop["width"], "Footpath"))

# Village streets first so country roads meet them at the right height.
RANK = {"Village street": 0, "Main road": 1, "Lane": 2, "Footpath": 3, "Mountain trail": 4}
order = sorted(roads, key=lambda r: RANK[r[3]])  # stable: keeps JSON order within a class
for rid, pts, width, cls in order:
    spec = ROAD_CLASS[cls]
    total = cumulative(pts)[-1]
    n = max(2, int(total / 2.0) + 1)
    s = np.linspace(0, total, n)
    cum = cumulative(pts)
    px = np.interp(s, cum, pts[:, 0])
    pz = np.interp(s, cum, pts[:, 1])
    h = np.array([sample(H, a, b) for a, b in zip(px, pz)])
    on_water = np.array([water_mask[int(round(b - ORIGIN)), int(round(a - ORIGIN))] for a, b in zip(px, pz)])
    # Across water the road is carried by a bridge at bank height: bridge the gap in the profile.
    if on_water.any() and not on_water.all():
        h[on_water] = np.interp(s[on_water], s[~on_water], h[~on_water])
    # Pin the road to the flat ground it passes through: plateaus and landmark pads.
    anchor = np.full(n, np.nan)
    vdist = np.hypot(px / 150.0, pz / 170.0)
    farm_d = np.hypot(np.maximum(np.maximum(fx0 - px, px - fx1), 0), np.maximum(np.maximum(fz0 - pz, pz - fz1), 0))
    anchor = np.where((vdist <= 0.92) & (farm_d > 30.0), 10.0 + smoothstep(-88, -108, pz), anchor)
    in_farm = (px >= fx0) & (px <= fx1) & (pz >= fz0) & (pz <= fz1)
    anchor = np.where(in_farm, 8.0, anchor)
    for ax, az, ar, ay in pads:
        anchor = np.where(np.hypot(px - ax, pz - az) <= ar + 1.0, ay, anchor)
    # Where this road meets a road already laid, take that road's surface height.
    ij = (np.clip(np.round(pz - ORIGIN), 0, N - 1).astype(int), np.clip(np.round(px - ORIGIN), 0, N - 1).astype(int))
    on_road = road_core[ij]
    anchor = np.where(on_road, H[ij], anchor)
    pinned = ~np.isnan(anchor)
    h = np.where(pinned, anchor, h)
    # Smooth, then clamp the grade both ways without moving pinned samples.
    win = max(1, int(spec["smooth"] / 2.0))
    kernel = np.ones(2 * win + 1) / (2 * win + 1)
    h = np.convolve(np.pad(h, win, mode="edge"), kernel, mode="valid")
    h = np.where(pinned, anchor, h)
    step = spec["grade"] * (s[1] - s[0])
    for _ in range(4):
        for k in range(1, n):
            if not pinned[k]:
                h[k] = np.clip(h[k], h[k - 1] - step, h[k - 1] + step)
        for k in range(n - 2, -1, -1):
            if not pinned[k]:
                h[k] = np.clip(h[k], h[k + 1] - step, h[k + 1] + step)
    g = np.abs(np.diff(h)) / (s[1] - s[0])
    k = int(np.argmax(g))
    grade_report.append((rid, cls, float(g[k]), spec["grade"], (round(px[k]), round(pz[k]), round(h[k], 1), round(h[k + 1], 1))))

    # Measure along the original polyline: the 2 m resampling cuts corners, so its own arc length
    # would drift from s on winding roads.
    dist, along = polyline_distance(pts, pad=width / 2 + spec["shoulder"] + spec["falloff"] + 2)
    finite = np.isfinite(dist)
    road_h = np.interp(along, s, h)
    core = width / 2 + spec["shoulder"]
    w = np.where(dist <= core, 1.0, smoothstep(core + spec["falloff"], core, dist))
    w = np.where(finite & ~water_mask & ~protected & ~road_core, w, 0.0)
    H = H * (1 - w) + road_h * w
    road_core |= finite & (dist <= width / 2) & ~water_mask
    paint = np.where(finite, smoothstep(width / 2 + 0.6, width / 2 - 0.4, dist), 0.0)
    if cls == "Village street":
        road_cobble = np.maximum(road_cobble, paint)
    else:
        road_dirt = np.maximum(road_dirt, paint * (0.75 if cls in ("Footpath", "Mountain trail") else 1.0))


# Final pass: re-read each road from the finished terrain (corridors overlap at junctions and
# hairpins) and re-level it in place with the same grade limit, keeping pads and plateaus fixed.
for _ in range(2):
    taken = np.zeros((N, N), dtype=bool)  # centre strips of higher-priority roads re-levelled this pass
    for rid, pts, width, cls in order:
        spec = ROAD_CLASS[cls]
        cum = cumulative(pts)
        n = max(2, int(cum[-1]) + 1)
        s = np.linspace(0, cum[-1], n)
        px = np.interp(s, cum, pts[:, 0])
        pz = np.interp(s, cum, pts[:, 1])
        ij = (np.clip(np.round(pz - ORIGIN), 0, N - 1).astype(int), np.clip(np.round(px - ORIGIN), 0, N - 1).astype(int))
        h = np.array([sample(H, a, b) for a, b in zip(px, pz)])
        fixed = protected[ij] | water_mask[ij] | taken[ij]
        step = spec["grade"] * (s[1] - s[0])
        for _pass in range(4):
            for k in range(1, n):
                if not fixed[k]:
                    h[k] = np.clip(h[k], h[k - 1] - step, h[k - 1] + step)
            for k in range(n - 2, -1, -1):
                if not fixed[k]:
                    h[k] = np.clip(h[k], h[k + 1] - step, h[k + 1] + step)
        dist, along = polyline_distance(pts, pad=width / 2 + 2)
        core = np.isfinite(dist) & (dist <= width / 2 + spec["shoulder"]) & ~protected & ~water_mask & ~taken
        H = np.where(core, np.interp(along, s, h), H)
        taken |= np.isfinite(dist) & (dist <= width / 2) & ~water_mask


# --- 5. ground-type maps ---------------------------------------------------------------------------
slope = np.degrees(np.arctan(np.hypot(*np.gradient(H))))

soil = np.zeros((N, N))
cobble = road_cobble.copy()
SOIL_AREAS = {"starter_field", "kitchen_garden", "community_garden"}
COBBLE_AREAS = {"public_square", "marketplace"}
for lm in layout["landmarks"]:
    fp = lm.get("footprint")
    if not fp:
        continue
    x, _, z = lm["position"]
    inside_rect = (np.abs(X - x) <= fp[0] / 2) & (np.abs(Z - z) <= fp[1] / 2)
    if lm["id"] in SOIL_AREAS:
        soil = np.maximum(soil, inside_rect * 1.0)
    if lm["id"] in COBBLE_AREAS:
        cobble = np.maximum(cobble, inside_rect * 1.0)

sand = np.zeros((N, N))
sand = np.maximum(sand, river_bed * 1.0)
sand = np.maximum(sand, ((lake_d >= 0.9) & (lake_d < 1.12)) * 1.0)

forest_floor = np.clip((-255.0 - X) / 30.0, 0, 1) * (Z > -270) * (Z < 390)
forest_floor = np.maximum(forest_floor, ((X > 430) & (Z > -300) & (Z < -100)) * 0.8)
forest_floor = ndimage.gaussian_filter(forest_floor.astype(np.float64), 6)
meadow_flowers = smoothstep(290, 330, Z) * (0.5 + 0.5 * value_noise(40, SEED + 9, 2))
rock = smoothstep(-250, -300, Z + edge_wobble)

control = np.stack([road_dirt, soil, sand, cobble], axis=-1)
zones = np.stack([forest_floor, np.clip(meadow_flowers, 0, 1), rock], axis=-1)

# --- 6. write --------------------------------------------------------------------------------------
OUT_RAW.parent.mkdir(parents=True, exist_ok=True)
OUT_DIR.mkdir(parents=True, exist_ok=True)
H.astype("<f4").tofile(OUT_RAW)


def to_png(arr: np.ndarray, path: Path):
    img = (np.clip(arr[:-1, :-1], 0, 1) * 255 + 0.5).astype(np.uint8)  # 1024 x 1024 texels
    Image.fromarray(img).save(path)


to_png(control, OUT_DIR / "control.png")
to_png(zones, OUT_DIR / "zones.png")

# Shaded relief preview with water and roads, north up.
gx, gz = np.gradient(H)
light = np.clip(0.6 + (-gx * 0.7 - gz * 0.7) * 0.25, 0, 1)
hn = np.clip((H + 8) / 158.0, 0, 1)
col = np.stack([0.45 + 0.4 * hn, 0.62 + 0.25 * hn, 0.38 + 0.4 * hn], -1) * light[..., None]
col = np.where((H < 0.0)[..., None] & (lake_d < 1)[..., None], [0.3, 0.7, 0.8], col)
col = np.where(river_bed[..., None], [0.3, 0.7, 0.8], col)
col = np.where((road_dirt > 0.5)[..., None], [0.62, 0.48, 0.32], col)
col = np.where((cobble > 0.5)[..., None], [0.75, 0.7, 0.62], col)
Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8)).save(OUT_DIR / "heightmap_preview.png")

# --- 7. report -------------------------------------------------------------------------------------
print(f"height range {H.min():.1f} .. {H.max():.1f} m")
print("landmark heights (blueprint -> terrain):")
worst = 0.0
for lm in layout["landmarks"]:
    if lm["id"] in WATER_POINTS:
        continue
    x, y, z = lm["position"]
    t = sample(H, x, z)
    worst = max(worst, abs(t - y))
    if abs(t - y) > 0.3:
        print(f"  {lm['id']:<20} {y:6.1f} -> {t:6.1f}")
print(f"  worst landmark error {worst:.2f} m")
print("road grades (max / limit):")
bridges = [(b["position"][0], b["position"][2]) for b in layout["bridges"]]
final_report = {}
for rid, pts, width, cls in roads:
    cum = cumulative(pts)
    s2 = np.arange(0, cum[-1], 2.0)
    qx = np.interp(s2, cum, pts[:, 0])
    qz = np.interp(s2, cum, pts[:, 1])
    qh = np.array([sample(H, a, b) for a, b in zip(qx, qz)])
    skip = np.array([water_mask[int(round(b - ORIGIN)), int(round(a - ORIGIN))] or any(math.hypot(a - bx, b - bz) < 14 for bx, bz in bridges) for a, b in zip(qx, qz)])
    g = np.abs(np.diff(qh)) / 2.0
    g[skip[:-1] | skip[1:]] = 0
    g[:2] = 0
    g[-2:] = 0
    k = int(np.argmax(g)) if g.size else 0
    final_report[rid] = (float(g[k]) if g.size else 0.0, (round(qx[k]), round(qz[k])) if g.size else None)
for rid, cls, g, lim, where in grade_report:
    fg, fwhere = final_report[rid]
    if fg > lim + 0.01:
        print(f"  {rid:<4} FINAL TERRAIN {fg * 100:5.1f}% / {lim * 100:.0f}%   <-- at {fwhere}")
    flag = "" if g <= lim + 1e-3 else f"   <-- at {where}"
    print(f"  {rid:<4} {cls:<15} {g * 100:5.1f}% / {lim * 100:.0f}%{flag}")
print(f"walkable share (< 40 deg): {(slope < 40).mean() * 100:.1f}%")
