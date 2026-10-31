"""Haven Valley – Phase 2C blockout generator for Blender (4.2 LTS or newer).

Builds every village and farm building, the village house and market-stall variants, and the
nature kit (trees, bushes, rocks) as low-poly stylized blockouts, then exports each one as a GLB
into the Godot project:

    assets/buildings/blockout/<id>.glb      buildings (mesh + "-col" trimesh collision)
    assets/environment/nature/<id>.glb      trees, bushes and rocks (mesh only)
    art_source/blender/haven_blockouts.blend   every asset laid out in a grid, for editing

Building sizes and facings are read from resources/world/world_layout.json, so a model always fits
its blueprint footprint.

Conventions (shared with scripts/world/greybox_builder.gd and nature_scatter.gd):
  * 1 Blender unit = 1 metre. Origin = centre of the footprint at floor level.
  * The front (door side) faces Blender -Y, which is +Z (south) in Godot. Godot rotates the model
    to the landmark's "faces" direction.
  * Model width (X) runs along the front; depth (Y) runs front to back.
  * Buildings stand on a stone plinth whose top is 0.3 m above the origin and whose bottom is 2 m
    below it, so the building can sit on uneven ground without floating.

Run from the command line (no UI needed):
    blender --background --factory-startup --python tools/blender/haven_blockouts.py

Or from Blender's Text Editor / the Blender MCP server: run this file. In a running Blender the
script starts a second, background Blender (same executable) to do the work, so your open file and
scenes are never touched; the result is printed and written to art_source/blender/blockout_report.json.
"""

import json
import math
import random
import subprocess
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

SCENE_NAME = "HavenBlockouts"
PLINTH_TOP = 0.3
PLINTH_DEPTH = 2.0

# --- Paths ------------------------------------------------------------------------------------------


def project_root() -> Path:
    """The Godot project folder: --project <path>, or the first folder above this script with project.godot."""
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--project" in args:
        return Path(args[args.index("--project") + 1]).resolve()
    candidates = []
    if "__file__" in globals():
        candidates.append(Path(__file__))
    # Run from Blender's Text Editor, __file__ is only the text block name; use the text's file path.
    for text in bpy.data.texts:
        if text.filepath and text.name.startswith("haven_blockouts"):
            candidates.append(Path(bpy.path.abspath(text.filepath)))
    candidates.append(Path.home() / "Documents" / "HavenValley" / "tools" / "blender" / "haven_blockouts.py")
    for candidate in candidates:
        for folder in candidate.resolve().parents:
            if (folder / "project.godot").is_file():
                return folder
    raise RuntimeError("Haven Valley project not found. Run: blender -b --python haven_blockouts.py -- --project <path>")


ROOT = project_root()
LAYOUT_PATH = ROOT / "resources" / "world" / "world_layout.json"
BUILDING_DIR = ROOT / "assets" / "buildings" / "blockout"
NATURE_DIR = ROOT / "assets" / "environment" / "nature"
BLEND_PATH = ROOT / "art_source" / "blender" / "haven_blockouts.blend"

# --- Palette (sRGB hex) -----------------------------------------------------------------------------

PALETTE = {
    "Plaster": ("efe2c6", 0.95),
    "PlasterWarm": ("e8c99a", 0.95),
    "Timber": ("8a6240", 0.9),
    "TimberDark": ("4e3424", 0.9),
    "TimberGrey": ("8d8a80", 0.9),
    "BarnRed": ("a33f2c", 0.9),
    "Stone": ("a39d90", 0.95),
    "StoneDark": ("6f6a63", 0.95),
    "RoofRed": ("b8452e", 0.8),
    "RoofBlue": ("4a6e8c", 0.8),
    "RoofGreen": ("5e7f45", 0.8),
    "RoofSlate": ("5c5f6b", 0.8),
    "RoofThatch": ("c9a45c", 0.95),
    "Glass": ("9fd0e0", 0.2),
    "Door": ("5a3d22", 0.9),
    "Trim": ("f6f1e6", 0.9),
    "Gold": ("e2a800", 0.4),
    "ClothRed": ("d0563f", 0.95),
    "ClothBlue": ("4f86b8", 0.95),
    "ClothYellow": ("e8b23a", 0.95),
    "Bark": ("6b4a2e", 0.95),
    "BarkBirch": ("e9e4d8", 0.95),
    "LeafOak": ("5a9a3c", 0.9),
    "LeafOakDark": ("447a30", 0.9),
    "LeafPine": ("2f5d3a", 0.9),
    "LeafPineLight": ("3d7146", 0.9),
    "LeafBirch": ("8dbb4a", 0.9),
    "LeafBush": ("4f8a3a", 0.9),
    "Rock": ("8f8b84", 0.95),
    "RockMoss": ("7d8a66", 0.95),
}


def srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def material(name: str) -> bpy.types.Material:
    mat = bpy.data.materials.get("HV_" + name)
    if mat:
        return mat
    hex_value, roughness = PALETTE[name]
    rgb = [srgb_to_linear(int(hex_value[i:i + 2], 16) / 255.0) for i in (0, 2, 4)]
    mat = bpy.data.materials.new("HV_" + name)
    mat.diffuse_color = (*rgb, 1.0)
    mat.roughness = roughness
    if bpy.app.version < (5, 0, 0):
        mat.use_nodes = True  # Blender 5 materials always use nodes (the property is deprecated there)
    if mat.node_tree:
        bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf:
            bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
            bsdf.inputs["Roughness"].default_value = roughness
            bsdf.inputs["Metallic"].default_value = 0.0
    return mat


# --- Mesh builder -----------------------------------------------------------------------------------


class Model:
    """Collects flat-shaded parts into one bmesh with one material slot per palette entry."""

    def __init__(self, name: str):
        self.name = name
        self.bm = bmesh.new()
        self.materials: list[str] = []
        self.offset = Matrix.Identity(4)  # applied to every part added (used to shift sub-assemblies)

    def _index(self, mat: str) -> int:
        if mat not in self.materials:
            self.materials.append(mat)
        return self.materials.index(mat)

    def _face(self, verts, mat: str) -> None:
        face = self.bm.faces.new(verts)
        face.material_index = self._index(mat)
        face.smooth = False

    def loft(self, rings, mat: str, side_mats=None, cap_mat=None, matrix: Matrix | None = None) -> None:
        """Connect consecutive rings of points with quads (or triangles to a 1-point ring); cap the ends."""
        m = self.offset @ (matrix or Matrix.Identity(4))
        verts = [[self.bm.verts.new(m @ Vector(p)) for p in ring] for ring in rings]
        for a, b in zip(verts, verts[1:]):
            if len(a) == 1 and len(b) == 1:
                continue
            if len(a) == 1:
                for j in range(len(b)):
                    self._face((a[0], b[(j + 1) % len(b)], b[j]), mat)
            elif len(b) == 1:
                for j in range(len(a)):
                    self._face((a[j], a[(j + 1) % len(a)], b[0]), mat)
            else:
                n = len(a)
                for j in range(n):
                    side = side_mats[j] if side_mats else mat
                    self._face((a[j], a[(j + 1) % n], b[(j + 1) % n], b[j]), side)
        if len(verts[0]) > 2:
            self._face(list(reversed(verts[0])), cap_mat or mat)
        if len(verts[-1]) > 2:
            self._face(verts[-1], cap_mat or mat)

    def build(self, collection: bpy.types.Collection, object_name: str | None = None) -> bpy.types.Object:
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces[:])
        mesh = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for mat in self.materials:
            mesh.materials.append(material(mat))
        obj = bpy.data.objects.new(object_name or self.name, mesh)
        collection.objects.link(obj)
        return obj


def rect(cx, cy, sx, sy, z):
    hx, hy = sx * 0.5, sy * 0.5
    return [(cx - hx, cy - hy, z), (cx + hx, cy - hy, z), (cx + hx, cy + hy, z), (cx - hx, cy + hy, z)]


def box(m: Model, cx, cy, z0, sx, sy, sz, mat, matrix=None):
    m.loft([rect(cx, cy, sx, sy, z0), rect(cx, cy, sx, sy, z0 + sz)], mat, matrix=matrix)


def circle(cx, cy, r, z, segments, phase=0.0):
    return [(cx + r * math.cos(phase + 2 * math.pi * i / segments), cy + r * math.sin(phase + 2 * math.pi * i / segments), z)
            for i in range(segments)]


def cylinder(m: Model, cx, cy, z0, r0, r1, h, segments, mat, matrix=None, phase=0.0):
    top = [(cx, cy, z0 + h)] if r1 <= 0 else circle(cx, cy, r1, z0 + h, segments, phase)
    m.loft([circle(cx, cy, r0, z0, segments, phase), top], mat, matrix=matrix)


def gable(m: Model, cx, cy, z0, length, depth, rise, roof_mat, end_mat, matrix=None):
    """Gable roof prism, ridge along X. Gable-end triangles use end_mat."""
    rings = []
    for x in (cx - length * 0.5, cx + length * 0.5):
        rings.append([(x, cy - depth * 0.5, z0), (x, cy + depth * 0.5, z0), (x, cy, z0 + rise)])
    m.loft(rings, roof_mat, side_mats=[roof_mat, roof_mat, roof_mat], cap_mat=end_mat, matrix=matrix)


def pyramid(m: Model, cx, cy, z0, sx, sy, h, mat):
    m.loft([rect(cx, cy, sx, sy, z0), [(cx, cy, z0 + h)]], mat)


def blob(m: Model, centre, radii, mat, rng: random.Random, segments=7, rings=4, jitter=0.12, flat_bottom=None):
    cx, cy, cz = centre
    rx, ry, rz = radii
    pts = [[(cx, cy, cz - rz if flat_bottom is None else max(cz - rz, flat_bottom))]]
    phase = rng.random() * math.pi
    for i in range(1, rings):
        lat = -math.pi / 2 + math.pi * i / rings
        ring = []
        for j in range(segments):
            lon = phase + 2 * math.pi * j / segments
            k = 1.0 + rng.uniform(-jitter, jitter)
            z = cz + rz * math.sin(lat) * k
            if flat_bottom is not None:
                z = max(z, flat_bottom)
            ring.append((cx + rx * math.cos(lat) * math.cos(lon) * k, cy + ry * math.cos(lat) * math.sin(lon) * k, z))
        pts.append(ring)
    pts.append([(cx, cy, cz + rz)])
    m.loft(pts, mat)


# --- Building kit -----------------------------------------------------------------------------------


def plinth(m: Model, w, d, mat="Stone"):
    box(m, 0, 0, -PLINTH_DEPTH, w, d, PLINTH_DEPTH + PLINTH_TOP, mat)


def door(m: Model, x, y_front, width=1.3, height=2.3, mat="Door", side="front", w=0.0):
    if side == "front":
        box(m, x, y_front - 0.05, PLINTH_TOP, width, 0.14, height, mat)
        box(m, x, y_front - 0.08, PLINTH_TOP + height, width + 0.3, 0.16, 0.18, "TimberDark")
        box(m, x, y_front - 0.75, PLINTH_TOP - 0.45, width + 1.0, 1.2, 0.45, "Stone")  # step


def window(m: Model, x, y, z, width=1.1, height=1.1, facing="front"):
    if facing == "front":
        box(m, x, y - 0.04, z, width, 0.1, height, "Glass")
        box(m, x, y - 0.08, z - 0.12, width + 0.3, 0.18, 0.12, "Trim")
        box(m, x, y - 0.06, z + height * 0.5 - 0.04, width, 0.12, 0.08, "Trim")
    elif facing in ("left", "right"):
        s = -1 if facing == "left" else 1
        box(m, y + s * 0.04, x, z, 0.1, width, height, "Glass")
        box(m, y + s * 0.08, x, z - 0.12, 0.18, width + 0.3, 0.12, "Trim")
    elif facing == "back":
        box(m, x, y + 0.04, z, width, 0.1, height, "Glass")
        box(m, x, y + 0.08, z - 0.12, width + 0.3, 0.18, 0.12, "Trim")


def window_slots(width, door_x=None, door_w=1.3, spacing=2.6):
    count = max(1, int((width - 1.6) // spacing))
    usable = width - 2.0
    xs = [-usable * 0.5 + usable * (i + 0.5) / count for i in range(count)]
    if door_x is not None:
        xs = [x for x in xs if abs(x - door_x) > door_w * 0.5 + 0.9]
    return xs


def building(m: Model, w, d, wall_h, roof_rise, wall_mat="Plaster", roof_mat="RoofRed", *, door_x=0.0, door_w=1.3,
             storeys=1, timber=True, chimney=None, side_windows=True, roof_overhang=0.6, plinth_mat="Stone"):
    """Generic cottage/shop shell: plinth, walls, timber corners, gable roof, door, windows, chimney."""
    plinth(m, w + 0.4, d + 0.4, plinth_mat)
    box(m, 0, 0, PLINTH_TOP, w, d, wall_h, wall_mat)
    top = PLINTH_TOP + wall_h
    if timber:
        for sx in (-1, 1):
            for sy in (-1, 1):
                box(m, sx * (w * 0.5 - 0.12), sy * (d * 0.5 - 0.12), PLINTH_TOP, 0.34, 0.34, wall_h, "TimberDark")
        for sy in (-1, 1):
            box(m, 0, sy * (d * 0.5 + 0.02), top - 0.3, w + 0.1, 0.3, 0.3, "TimberDark")
        if storeys > 1:
            box(m, 0, -(d * 0.5 + 0.02), PLINTH_TOP + wall_h / storeys - 0.15, w + 0.1, 0.3, 0.25, "TimberDark")
    gable(m, 0, 0, top, w + roof_overhang * 2, d + roof_overhang * 2, roof_rise, roof_mat, wall_mat)
    if door_x is not None:
        door(m, door_x, -d * 0.5, door_w)
    storey_h = wall_h / storeys
    for s in range(storeys):
        z = PLINTH_TOP + s * storey_h + max(1.0, storey_h * 0.32)
        for x in window_slots(w, door_x if s == 0 else None, door_w):
            window(m, x, -d * 0.5, z)
        for x in window_slots(w, None):
            window(m, x, d * 0.5, z, facing="back")
        if side_windows:
            for y in window_slots(d, None, spacing=3.2):
                window(m, y, -w * 0.5, z, facing="left")
                window(m, y, w * 0.5, z, facing="right")
    if chimney:
        cx, cy = chimney
        box(m, cx, cy, top - 0.5, 0.9, 0.9, roof_rise + 1.4, "StoneDark")
    return top


def awning(m: Model, w, y_front, z, depth, mat):
    """Sloped canopy over the front, made from a thin wedge."""
    rings = [[(x, y_front, z + 0.6), (x, y_front - depth, z), (x, y_front - depth, z - 0.12), (x, y_front, z + 0.48)]
             for x in (-w * 0.5, w * 0.5)]
    m.loft(rings, mat)


def porch(m: Model, w, y_front, depth, z_roof, roof_mat):
    box(m, 0, y_front - depth * 0.5, PLINTH_TOP - 0.45, w, depth, 0.45, "Timber")
    for x in (-w * 0.5 + 0.2, w * 0.5 - 0.2):
        box(m, x, y_front - depth + 0.2, PLINTH_TOP, 0.22, 0.22, z_roof - PLINTH_TOP, "TimberDark")
    awning(m, w + 0.4, y_front, z_roof, depth + 0.3, roof_mat)


# --- Buildings --------------------------------------------------------------------------------------


def town_hall(m: Model, w, d):
    porch_d = 3.0
    m.offset = Matrix.Translation((0, porch_d * 0.5, 0))
    top = building(m, w, d - porch_d, 8.0, 5.0, "Plaster", "RoofRed", door_w=2.4, storeys=2, timber=False,
                   chimney=None, plinth_mat="Stone")
    m.offset = Matrix.Identity(4)
    # Portico inside the front of the footprint: four columns and a pediment over the main doors.
    front = -d * 0.5
    for x in (-4.5, -1.5, 1.5, 4.5):
        cylinder(m, x, front + 0.6, PLINTH_TOP, 0.42, 0.36, 6.0, 8, "Trim")
    box(m, 0, front + 1.5, -PLINTH_DEPTH, 11.0, 3.0, PLINTH_DEPTH + PLINTH_TOP, "Stone")
    box(m, 0, front + 1.5, PLINTH_TOP + 6.0, 11.0, 3.0, 0.6, "Trim")
    gable(m, 0, 0, PLINTH_TOP + 6.6, 3.0, 11.4, 1.8, "RoofRed", "Trim",
          matrix=Matrix.Translation((0, front + 1.5, 0)) @ Matrix.Rotation(math.radians(90), 4, "Z"))
    # Clock tower at the back (north): 6 x 6 m, roof tip 34 m above the floor.
    ty = d * 0.25
    box(m, 0, ty, PLINTH_TOP, 6.0, 6.0, 26.0, "Plaster")
    box(m, 0, ty, PLINTH_TOP + 26.0, 6.6, 6.6, 0.6, "Trim")
    for sx in (-1, 1):
        for sy in (-1, 1):
            box(m, sx * 2.8, ty + sy * 2.8, PLINTH_TOP + 26.6, 0.5, 0.5, 2.6, "Trim")  # belfry posts
    box(m, 0, ty, PLINTH_TOP + 29.2, 6.6, 6.6, 0.4, "Trim")
    pyramid(m, 0, ty, PLINTH_TOP + 29.6, 6.8, 6.8, 4.1, "RoofRed")
    # Clock faces on all four sides.
    rot_x = Matrix.Rotation(math.radians(90), 4, "X")
    for angle in (0, 90, 180, 270):
        place = Matrix.Translation((0, ty, PLINTH_TOP + 22.5)) @ Matrix.Rotation(math.radians(angle), 4, "Z") \
            @ Matrix.Translation((0, -3.05, 0)) @ rot_x
        cylinder(m, 0, 0, -0.1, 1.6, 1.6, 0.2, 16, "Trim", matrix=place)
        cylinder(m, 0, 0, -0.14, 0.18, 0.18, 0.3, 8, "Gold", matrix=place)
    return top


def general_store(m, w, d):
    top = building(m, w, d, 4.6, 3.4, "PlasterWarm", "RoofBlue", door_w=1.8, chimney=(w * 0.3, d * 0.2))
    awning(m, w - 1.0, -d * 0.5, PLINTH_TOP + 3.2, 1.8, "ClothBlue")
    box(m, 0, -d * 0.5 - 0.12, top - 1.05, w * 0.5, 0.12, 0.7, "Timber")  # shop sign board


def cafe(m, w, d):
    building(m, w, d, 4.2, 3.0, "Plaster", "RoofGreen", door_w=1.6, chimney=(-w * 0.25, d * 0.15))
    awning(m, w - 0.6, -d * 0.5, PLINTH_TOP + 3.0, 1.6, "ClothRed")


def restaurant(m, w, d):
    building(m, w, d, 6.4, 3.8, "PlasterWarm", "RoofRed", door_w=1.8, storeys=2, chimney=(w * 0.3, d * 0.2))
    awning(m, w * 0.6, -d * 0.5, PLINTH_TOP + 2.9, 1.5, "ClothYellow")


def blacksmith(m, w, d):
    main_w = w * 0.62
    m_shift = -(w - main_w) * 0.5
    plinth(m, w + 0.4, d + 0.4)
    box(m, m_shift, 0, PLINTH_TOP, main_w, d, 4.0, "Stone")
    gable(m, m_shift, 0, PLINTH_TOP + 4.0, main_w + 1.0, d + 1.0, 2.8, "RoofSlate", "Stone")
    door(m, m_shift, -d * 0.5, 1.6)
    window(m, m_shift + main_w * 0.3, -d * 0.5, 1.6)
    box(m, m_shift - main_w * 0.3, d * 0.2, PLINTH_TOP + 2.0, 1.4, 1.4, 6.2, "StoneDark")  # forge chimney
    # Open lean-to workshop on the right: posts, slanted roof, forge and anvil.
    lx0 = m_shift + main_w * 0.5
    lw = w * 0.5 - lx0
    for y in (-d * 0.5 + 0.3, d * 0.5 - 0.3):
        box(m, w * 0.5 - 0.3, y, PLINTH_TOP, 0.3, 0.3, 2.8, "TimberDark")
    rings = [[(x, -d * 0.5 - 0.4, PLINTH_TOP + 2.8), (x, d * 0.5 + 0.4, PLINTH_TOP + 2.8),
              (x, d * 0.5 + 0.4, PLINTH_TOP + 2.95), (x, -d * 0.5 - 0.4, PLINTH_TOP + 2.95)]
             for x in (lx0, w * 0.5 + 0.3)]
    rings = [[(p[0], p[1], p[2] + (0.9 if p[0] == lx0 else 0.0)) for p in r] for r in rings]
    m.loft(rings, "RoofSlate")
    box(m, lx0 + lw * 0.5, d * 0.2, PLINTH_TOP, 1.6, 1.4, 1.0, "StoneDark")  # forge
    box(m, lx0 + lw * 0.5, -d * 0.2, PLINTH_TOP, 0.5, 1.0, 0.8, "RoofSlate")  # anvil


def carpenter(m, w, d):
    m.offset = Matrix.Translation((-w * 0.125, 0, 0))
    building(m, w * 0.75 - 0.6, d - 1.2, 4.6, 3.4, "Timber", "RoofRed", door_w=2.6, chimney=None)
    m.offset = Matrix.Identity(4)
    box(m, w * 0.375, 0, -PLINTH_DEPTH, w * 0.25, d, PLINTH_DEPTH + PLINTH_TOP - 0.1, "Timber")
    # Covered lumber stack beside the workshop (inside the footprint).
    for i in range(3):
        box(m, w * 0.375, -d * 0.2 + i * 1.1, PLINTH_TOP, w * 0.2, 0.9, 0.5 + 0.3 * (i % 2), "Timber")
    m.loft([[(x, -d * 0.5, PLINTH_TOP + 2.6), (x, d * 0.5, PLINTH_TOP + 2.6), (x, d * 0.5, PLINTH_TOP + 2.75),
             (x, -d * 0.5, PLINTH_TOP + 2.75)] for x in (w * 0.25, w * 0.5)], "RoofRed")
    for y in (-d * 0.5 + 0.2, d * 0.5 - 0.2):
        box(m, w * 0.5 - 0.15, y, PLINTH_TOP, 0.25, 0.25, 2.6, "TimberDark")


def storage_delivery(m, w, d):
    building(m, w, d, 6.0, 2.6, "TimberGrey", "RoofSlate", door_x=None, timber=True, side_windows=False)
    box(m, -w * 0.2, -d * 0.5 - 0.06, PLINTH_TOP, 4.5, 0.14, 4.2, "Door")  # big sliding doors
    box(m, w * 0.2, -d * 0.5 - 0.06, PLINTH_TOP, 4.5, 0.14, 4.2, "Door")
    box(m, 0, -d * 0.5 - 1.2, PLINTH_TOP - 0.5, w * 0.9, 2.4, 0.5, "Timber")  # loading platform
    box(m, 0, -d * 0.5 - 0.1, PLINTH_TOP + 4.6, w * 0.4, 0.14, 0.9, "Trim")  # sign


def farmhouse(m, w, d):
    top = building(m, w, d, 6.0, 3.8, "Plaster", "RoofRed", door_w=1.4, storeys=2, chimney=(w * 0.3, d * 0.15))
    porch(m, w * 0.7, -d * 0.5, 2.0, PLINTH_TOP + 2.8, "RoofRed")


def well(m, w, d):
    cylinder(m, 0, 0, -0.5, w * 0.42, w * 0.42, 1.4, 10, "Stone")
    cylinder(m, 0, 0, 0.85, w * 0.3, w * 0.3, 0.06, 10, "Glass")  # water surface
    for x in (-w * 0.38, w * 0.38):
        box(m, x, 0, 0.9, 0.16, 0.16, 1.7, "TimberDark")
    box(m, 0, 0, 2.2, w * 0.8, 0.12, 0.12, "TimberDark")
    gable(m, 0, 0, 2.55, w * 0.95, w * 0.75, 0.8, "RoofRed", "Timber")


def barn(m, w, d):
    plinth(m, w + 0.4, d + 0.4)
    box(m, 0, 0, PLINTH_TOP, w, d, 5.0, "BarnRed")
    # Gambrel roof (two pitches), ridge along X.
    z = PLINTH_TOP + 5.0
    o = 0.6
    rings = []
    for x in (-w * 0.5 - o, w * 0.5 + o):
        rings.append([(x, -d * 0.5 - o, z), (x, d * 0.5 + o, z), (x, d * 0.3, z + 2.8), (x, 0, z + 4.2), (x, -d * 0.3, z + 2.8)])
    m.loft(rings, "RoofSlate", cap_mat="BarnRed")
    for x in (-w * 0.5, w * 0.5):
        for y in (-d * 0.5, d * 0.5):
            box(m, x, y, PLINTH_TOP, 0.4, 0.4, 5.0, "Trim")
    box(m, 0, -d * 0.5 - 0.06, PLINTH_TOP, 5.2, 0.14, 4.4, "BarnRed")  # big doors
    for sx in (-1, 1):
        box(m, sx * 2.6, -d * 0.5 - 0.1, PLINTH_TOP, 0.25, 0.16, 4.4, "Trim")
    box(m, 0, -d * 0.5 - 0.1, PLINTH_TOP + 4.3, 5.4, 0.16, 0.25, "Trim")
    rot = Matrix.Translation((0, -d * 0.5 - 0.14, PLINTH_TOP + 2.2))
    for angle in (49, -49):  # the white X across the doors
        box(m, 0, 0, -0.12, 6.4, 0.08, 0.24, "Trim", matrix=rot @ Matrix.Rotation(math.radians(angle), 4, "Y"))
    window(m, 0, -d * 0.5, PLINTH_TOP + 6.0, 1.4, 1.2)  # hayloft


def coop(m, w, d):
    plinth(m, w + 0.2, d + 0.2, "Timber")
    box(m, -w * 0.15, 0, PLINTH_TOP + 0.4, w * 0.7, d * 0.8, 2.0, "Plaster")
    gable(m, -w * 0.15, 0, PLINTH_TOP + 2.4, w * 0.7 + 0.8, d * 0.8 + 0.8, 1.2, "RoofRed", "Plaster")
    door(m, -w * 0.15, -d * 0.4, 0.8, 1.2)
    # Fenced run on the right.
    rx0, rx1 = w * 0.2, w * 0.5
    for x in (rx0, rx1):
        for y in (-d * 0.4, 0, d * 0.4):
            box(m, x, y, PLINTH_TOP, 0.1, 0.1, 1.2, "TimberDark")
    for y in (-d * 0.4, d * 0.4):
        box(m, (rx0 + rx1) * 0.5, y, PLINTH_TOP + 0.9, rx1 - rx0, 0.06, 0.08, "TimberDark")
    box(m, rx1, 0, PLINTH_TOP + 0.9, 0.06, d * 0.8, 0.08, "TimberDark")


def storage_bld(m, w, d):
    building(m, w, d, 4.0, 2.8, "Timber", "RoofGreen", door_w=2.4, side_windows=False)


def greenhouse(m, w, d):
    plinth(m, w + 0.2, d + 0.2)
    box(m, 0, 0, PLINTH_TOP, w, d, 0.5, "Stone")
    box(m, 0, 0, PLINTH_TOP + 0.5, w - 0.1, d - 0.1, 2.4, "Glass")
    gable(m, 0, 0, PLINTH_TOP + 2.9, w, d, 1.6, "Glass", "Glass")
    for i in range(7):
        x = -w * 0.5 + w * i / 6
        for y in (-d * 0.5, d * 0.5):
            box(m, x, y, PLINTH_TOP + 0.5, 0.12, 0.12, 2.4, "Trim")
    box(m, 0, -d * 0.5 - 0.05, PLINTH_TOP + 0.5, 1.4, 0.1, 2.1, "Trim")  # door frame


def old_mill(m, w, d):
    bw = w - 2.6  # leave room on the right for the water wheel
    shift = -1.3
    box(m, shift, 0, -PLINTH_DEPTH, bw + 0.4, d + 0.4, PLINTH_DEPTH + PLINTH_TOP, "Stone")
    box(m, shift, 0, PLINTH_TOP, bw, d, 3.2, "Stone")
    box(m, shift, 0, PLINTH_TOP + 3.2, bw, d, 3.2, "Timber")
    gable(m, shift, 0, PLINTH_TOP + 6.4, bw + 1.2, d + 1.2, 3.4, "RoofThatch", "Timber")
    door(m, shift, -d * 0.5, 1.6)
    for z in (1.4, 4.4):
        window(m, shift + bw * 0.3, -d * 0.5, z)
    # Water wheel on the right wall, axle along X.
    wheel = Matrix.Translation((w * 0.5 - 0.9, 0, 2.6)) @ Matrix.Rotation(math.radians(90), 4, "Y")
    cylinder(m, 0, 0, -0.6, 2.9, 2.9, 1.2, 14, "Timber", matrix=wheel)
    cylinder(m, 0, 0, -1.4, 0.3, 0.3, 2.2, 8, "TimberDark", matrix=wheel)
    for i in range(7):
        a = Matrix.Rotation(math.radians(i * 360 / 14), 4, "Z")
        box(m, 0, 0, -0.65, 6.1, 0.18, 1.3, "TimberDark", matrix=wheel @ a)


def fisher_cottage(m, w, d):
    building(m, w, d, 3.8, 2.8, "TimberGrey", "RoofBlue", door_x=-w * 0.15, chimney=(w * 0.25, d * 0.2))
    porch(m, w * 0.6, -d * 0.5, 1.6, PLINTH_TOP + 2.6, "RoofBlue")


def house(variant):
    def make(m, w, d):
        if variant == "a":
            building(m, w, d, 4.0, 3.2, "Plaster", "RoofRed", door_x=-1.2, chimney=(w * 0.25, d * 0.2))
        elif variant == "b":
            building(m, w, d, 5.6, 3.0, "PlasterWarm", "RoofBlue", door_x=1.2, storeys=2, chimney=(-w * 0.25, d * 0.2))
        else:
            building(m, w, d, 3.8, 3.4, "Stone", "RoofGreen", door_x=0.0, timber=False, chimney=(w * 0.25, -d * 0.1))
            porch(m, w * 0.6, -d * 0.5, 1.4, PLINTH_TOP + 2.6, "RoofGreen")
    return make


def stall(cloth):
    def make(m, w, d):
        box(m, 0, 0, -0.4, w, d, 0.5, "Timber")
        box(m, 0, -d * 0.25, 0.1, w - 0.3, d * 0.35, 0.9, "Timber")  # counter
        box(m, 0, -d * 0.25, 1.0, w - 0.1, d * 0.45, 0.08, "TimberDark")
        for sx in (-1, 1):
            for sy in (-1, 1):
                box(m, sx * (w * 0.5 - 0.12), sy * (d * 0.5 - 0.12), 0.1, 0.14, 0.14, 2.3 + (0.4 if sy > 0 else 0), "TimberDark")
        rings = [[(x, -d * 0.5 - 0.3, 2.35), (x, d * 0.5 + 0.1, 2.85), (x, d * 0.5 + 0.1, 2.93), (x, -d * 0.5 - 0.3, 2.43)]
                 for x in (-w * 0.5 - 0.2, w * 0.5 + 0.2)]
        m.loft(rings, cloth)
        for i, mat in enumerate(("ClothRed", "ClothYellow", "LeafBush")):  # produce crates
            box(m, -w * 0.3 + i * w * 0.3, -d * 0.25, 1.08, 0.7, 0.5, 0.25, mat)
    return make


BUILDINGS = {
    "town_hall": town_hall, "general_store": general_store, "cafe": cafe, "restaurant": restaurant,
    "blacksmith": blacksmith, "carpenter": carpenter, "storage_delivery": storage_delivery,
    "farmhouse": farmhouse, "well": well, "barn": barn, "coop": coop, "storage_bld": storage_bld,
    "greenhouse": greenhouse, "old_mill": old_mill, "fisher_cottage": fisher_cottage,
}
VARIANTS = {
    "house_a": (house("a"), (8, 8)), "house_b": (house("b"), (8, 8)), "house_c": (house("c"), (8, 8)),
    "stall_a": (stall("ClothRed"), (4, 3)), "stall_b": (stall("ClothBlue"), (4, 3)), "stall_c": (stall("ClothYellow"), (4, 3)),
}

# --- Nature kit -------------------------------------------------------------------------------------


def pine(height, layers, seed):
    def make(m: Model):
        rng = random.Random(seed)
        cylinder(m, 0, 0, -0.3, 0.32, 0.22, height * 0.3 + 0.3, 6, "Bark")
        z = height * 0.2
        for i in range(layers):
            t = i / max(1, layers - 1)
            r = (1.0 - 0.65 * t) * height * 0.26
            h = height * (0.42 - 0.12 * t)
            cylinder(m, 0, 0, z, r, 0, h, 7, "LeafPine" if i % 2 == 0 else "LeafPineLight", phase=rng.random())
            z += h * 0.5
    return make


def broadleaf(height, clusters, leaf, bark, seed, trunk_r=0.3):
    def make(m: Model):
        rng = random.Random(seed)
        cylinder(m, 0, 0, -0.3, trunk_r, trunk_r * 0.7, height * 0.55 + 0.3, 6, bark)
        crown_z = height * 0.62
        crown_r = height * 0.28
        blob(m, (0, 0, crown_z), (crown_r, crown_r, crown_r * 0.85), leaf, rng)
        for i in range(clusters):
            a = 2 * math.pi * i / clusters + rng.uniform(-0.3, 0.3)
            dist = crown_r * rng.uniform(0.55, 0.8)
            r = crown_r * rng.uniform(0.55, 0.75)
            blob(m, (math.cos(a) * dist, math.sin(a) * dist, crown_z + rng.uniform(-0.4, 0.8)), (r, r, r * 0.85),
                 leaf if i % 2 else leaf + "Dark" if leaf + "Dark" in PALETTE else leaf, rng)
    return make


def bush(size, clusters, seed):
    def make(m: Model):
        rng = random.Random(seed)
        for i in range(clusters):
            a = 2 * math.pi * i / clusters
            r = size * rng.uniform(0.4, 0.55)
            blob(m, (math.cos(a) * size * 0.3, math.sin(a) * size * 0.3, r * 0.6), (r, r, r * 0.8), "LeafBush", rng,
                 flat_bottom=-0.1)
    return make


def rock(size, seed, mossy=False):
    def make(m: Model):
        rng = random.Random(seed)
        blob(m, (0, 0, size * 0.25), (size * 0.6, size * 0.5, size * 0.42), "RockMoss" if mossy else "Rock", rng,
             segments=7, rings=4, jitter=0.22, flat_bottom=-size * 0.15)
    return make


NATURE = {
    "tree_pine_a": pine(9.0, 4, 11), "tree_pine_b": pine(12.0, 5, 12), "tree_pine_c": pine(6.5, 3, 13),
    "tree_oak_a": broadleaf(8.0, 5, "LeafOak", "Bark", 21), "tree_oak_b": broadleaf(10.0, 6, "LeafOak", "Bark", 22, 0.38),
    "tree_birch_a": broadleaf(9.0, 4, "LeafBirch", "BarkBirch", 31, 0.2),
    "bush_a": bush(1.6, 4, 41), "bush_b": bush(2.4, 5, 42),
    "rock_a": rock(1.2, 51), "rock_b": rock(2.0, 52, True), "rock_c": rock(3.5, 53),
}

# --- Main -------------------------------------------------------------------------------------------


def model_size(landmark: dict) -> tuple[float, float]:
    """Width along the front and depth, from the blueprint footprint (world X, Z) and the facing."""
    fx, fz = landmark["footprint"]
    faces = (landmark.get("faces") or "S")[:1]
    return (fz, fx) if faces in ("E", "W") else (fx, fz)


def fresh_scene() -> bpy.types.Scene:
    """Background mode only: empty the startup scene and use it."""
    scene = bpy.context.scene
    for obj in list(scene.collection.all_objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    scene.name = SCENE_NAME
    bpy.context.view_layer.update()
    return scene


def export_glb(scene: bpy.types.Scene, obj: bpy.types.Object, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    view_layer = bpy.context.view_layer
    for other in view_layer.objects:
        if other is not None:
            other.select_set(False)
    obj.select_set(True)
    view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_cameras=False, export_lights=False)


def run_in_background() -> dict:
    """From an interactive Blender: run this script in a separate background Blender and read its report."""
    script = ROOT / "tools" / "blender" / "haven_blockouts.py"
    command = [bpy.app.binary_path, "--background", "--factory-startup", "--python-exit-code", "1", "--python", str(script), "--", "--project", str(ROOT)]
    done = subprocess.run(command, capture_output=True, text=True, timeout=600)
    report_path = BLEND_PATH.parent / "blockout_report.json"
    if done.returncode != 0 or "HAVEN_BLOCKOUTS_OK" not in done.stdout:
        raise RuntimeError("Background Blender failed:\n" + done.stdout[-3000:] + done.stderr[-3000:])
    return json.loads(report_path.read_text(encoding="utf-8"))


def mesh_size(obj: bpy.types.Object) -> list[float]:
    xs, ys, zs = zip(*(v.co[:] for v in obj.data.vertices))
    return [round(max(xs) - min(xs), 2), round(max(ys) - min(ys), 2), round(max(zs) - min(zs), 2)]


def main() -> dict:
    layout = json.loads(LAYOUT_PATH.read_text(encoding="utf-8"))
    landmarks = {lm["id"]: lm for lm in layout["landmarks"]}
    scene = fresh_scene()
    report = {"buildings": {}, "nature": {}}
    jobs = []
    for asset_id, make in BUILDINGS.items():
        w, d = model_size(landmarks[asset_id])
        jobs.append((asset_id, make, w, d, BUILDING_DIR, True))
    for asset_id, (make, (w, d)) in VARIANTS.items():
        jobs.append((asset_id, make, w, d, BUILDING_DIR, True))
    for asset_id, make in NATURE.items():
        jobs.append((asset_id, make, None, None, NATURE_DIR, False))

    objects = []
    for asset_id, make, w, d, folder, collide in jobs:
        model = Model(asset_id)
        if w is None:
            make(model)
        else:
            make(model, w, d)
        # "-col": Godot's importer keeps the mesh and adds a StaticBody3D with a trimesh shape.
        obj = model.build(scene.collection, asset_id + ("-col" if collide else ""))
        export_glb(scene, obj, folder / f"{asset_id}.glb")
        size = mesh_size(obj)
        report["buildings" if collide else "nature"][asset_id] = {"size": size, "tris": sum(len(p.vertices) - 2 for p in obj.data.polygons)}
        objects.append(obj)

    # Lay the assets out in a grid for browsing in the .blend (after export, so GLBs stay at the origin).
    x = 0.0
    for obj in objects:
        width = mesh_size(obj)[0]
        obj.location.x = x + width * 0.5
        x += width + 4.0
    BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.data.libraries.write(str(BLEND_PATH), {scene}, fake_user=True)
    report["blend"] = str(BLEND_PATH)
    report["blender"] = bpy.app.version_string
    (BLEND_PATH.parent / "blockout_report.json").write_text(json.dumps(report, indent=1), encoding="utf-8")
    return report


if bpy.app.background:
    result = main()
    print(json.dumps(result, indent=1))
    print("HAVEN_BLOCKOUTS_OK")
else:
    result = run_in_background()
    print(json.dumps(result, indent=1))
