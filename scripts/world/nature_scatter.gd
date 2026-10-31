@tool
class_name NatureScatter
extends Node3D
## Scatters trees, bushes and rocks over the valley from the Blender nature kit.
##
## Placement is deterministic (fixed seed) and follows the blueprint:
##   * how dense each kind is depends on the region (DENSITY) and on the zone map
##     (forest floor = thicker woods, rocky ground = more rocks); no trees above MAX_TREE_ALTITUDE;
##   * nothing is placed on roads, fields, sand or water (control map), on steep slopes,
##     or near buildings, landmarks, bridges and the player spawn.
## Instances are drawn with one MultiMeshInstance3D per chunk and model, so the GPU draws each
## model in each 125 m chunk with a single call. Tree trunks and rocks get simple collision shapes
## (one StaticBody3D per chunk) so the player cannot walk through them.

@export var layout_json: JSON
## The terrain to stand on. Must be earlier in the scene tree so it is built first.
@export var terrain: TerrainSystem
@export var control_map: Texture2D
@export var zone_map: Texture2D
@export_dir var nature_dir: String = "res://assets/environment/nature"
@export var random_seed: int = 20261031
## Spacing of the candidate grid in metres; each cell holds at most one plant or rock.
@export var cell_size: float = 4.0
## Scatter in the editor viewport as well (takes about a second).
@export var preview_in_editor: bool = true
@export_tool_button("Rebuild Preview", "Reload") var rebuild_button := rebuild

const WORLD_LAYER := 1
const KINDS := {
	"pine": ["tree_pine_a", "tree_pine_b", "tree_pine_c"],
	"broadleaf": ["tree_oak_a", "tree_oak_b", "tree_birch_a"],
	"bush": ["bush_a", "bush_b"],
	"rock": ["rock_a", "rock_b", "rock_c"],
}
## Instances per 100 m² by region id. Regions not listed get nothing (village, farm).
const DENSITY := {
	"forest": {"pine": 1.0, "broadleaf": 0.9, "bush": 0.7, "rock": 0.2},
	"mountain": {"pine": 0.9, "bush": 0.15, "rock": 0.2},
	"meadow": {"broadleaf": 0.04, "bush": 0.18, "rock": 0.05},
	"river": {"broadleaf": 0.15, "bush": 0.3, "rock": 0.1},
	"lake": {"broadleaf": 0.12, "bush": 0.25, "rock": 0.08},
	"valley": {"pine": 0.04, "broadleaf": 0.12, "bush": 0.2, "rock": 0.06},
}
## Base size (m) of each rock model, for its collision shape.
const ROCK_SIZE := {"rock_a": 1.2, "rock_b": 2.0, "rock_c": 3.5}
## Draw distances (0 = always drawn).
const VISIBILITY_END := {"pine": 0.0, "broadleaf": 0.0, "bush": 160.0, "rock": 260.0}
const MAX_TREE_ALTITUDE := 88.0
const MAX_TREE_SLOPE := 0.72  # minimum normal.y for trees and bushes (about 44 degrees)
const MAX_ROCK_SLOPE := 0.55
const KEEP_CLEAR := 4.0  # metres around buildings and areas
const POINT_CLEAR := 7.0  # metres around point landmarks (signs, viewpoints)
const SPAWN_CLEAR := 14.0
const ROAD_CLEAR := 2.5  # metres past the road edge, measured from the blueprint centre line

var _layout: WorldLayout
var _control: Image
var _zones: Image
var _meshes: Dictionary = {}  # model name -> Mesh
var _clear_rects: Array[Rect2] = []
var _clear_points: Array[Vector3] = []  # x, z, radius
var _roads: Array[Dictionary] = []  # {"points": PackedVector2Array, "clear": float, "bounds": Rect2}
## Model name -> PackedVector3Array of placed positions (read by tests and tools).
var placed: Dictionary = {}
var build_msec: int = 0


func _ready() -> void:
	if Engine.is_editor_hint() and not preview_in_editor:
		return
	rebuild()


## Delete the scattered children and scatter again.
func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	placed.clear()
	var start := Time.get_ticks_msec()
	_layout = WorldLayout.from_json(layout_json)
	if not _layout.is_valid() or terrain == null or control_map == null or zone_map == null:
		push_warning("NatureScatter: assign Layout Json, Terrain, Control Map and Zone Map.")
		return
	_control = control_map.get_image()
	_zones = zone_map.get_image()
	if _control.is_compressed():
		_control.decompress()
	if _zones.is_compressed():
		_zones.decompress()
	if not _load_meshes():
		return
	_collect_clear_areas()
	var chunks := _scatter()
	_build_chunks(chunks)
	build_msec = Time.get_ticks_msec() - start


## Total number of instances of the given kind ("pine", "broadleaf", "bush", "rock") or of all kinds.
func count(kind: String = "") -> int:
	var total := 0
	for model: String in placed:
		if kind == "" or KINDS.get(kind, []).has(model):
			total += (placed[model] as PackedVector3Array).size()
	return total


static func kind_of(model: String) -> String:
	for kind: String in KINDS:
		if KINDS[kind].has(model):
			return kind
	return ""


## Ground-cover values at a world position: x = road, y = tilled soil, z = sand/river bed, w = cobble.
func control_at(x: float, z: float) -> Vector4:
	var c := _sample(_control, x, z)
	return Vector4(c.r, c.g, c.b, c.a)


func _load_meshes() -> bool:
	_meshes.clear()
	for kind: String in KINDS:
		for model: String in KINDS[kind]:
			var path := nature_dir.path_join(model + ".glb")
			if not ResourceLoader.exists(path):
				push_warning("NatureScatter: missing %s (run tools/blender/haven_blockouts.py)." % path)
				continue
			var scene := load(path) as PackedScene
			var root := scene.instantiate()
			var mesh_instance := _find_mesh(root)
			if mesh_instance:
				_meshes[model] = mesh_instance.mesh
			root.free()
	return not _meshes.is_empty()


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_mesh(child)
		if found:
			return found
	return null


func _collect_clear_areas() -> void:
	_clear_rects.clear()
	_clear_points.clear()
	for landmark: Dictionary in _layout.get_landmarks():
		var p := WorldLayout.to_vec3(landmark["position"])
		var footprint = landmark.get("footprint")
		if landmark.get("id") == "mirror_lake":
			continue
		if footprint is Array:
			_add_rect(p.x, p.z, float(footprint[0]), float(footprint[1]), KEEP_CLEAR)
		else:
			_clear_points.append(Vector3(p.x, p.z, POINT_CLEAR))
	for key: String in ["village_houses", "market_stalls"]:
		for item: Dictionary in _layout.data.get(key, []):
			var p := WorldLayout.to_vec3(item["position"])
			var size: Array = item.get("footprint", [8, 8])
			_add_rect(p.x, p.z, float(size[0]), float(size[1]), KEEP_CLEAR)
	for zone: Dictionary in _layout.data.get("zones", []):
		if zone.get("type") == "build":
			var r: Array = zone["rect_xz"]
			_clear_rects.append(Rect2(r[0], r[1], r[2], r[3]))
	for bridge: Dictionary in _layout.data.get("bridges", []):
		var p := WorldLayout.to_vec3(bridge["position"])
		_clear_points.append(Vector3(p.x, p.z, float(bridge.get("span", 10)) * 0.5 + 8.0))
	var spawn := _layout.get_player_spawn()
	_clear_points.append(Vector3(spawn.x, spawn.z, SPAWN_CLEAR))
	# Road centre lines from the blueprint, so corners the painted road rounds off stay clear too.
	_roads.clear()
	for road: Dictionary in _layout.data.get("roads", []):
		var points := PackedVector2Array()
		for p: Array in road.get("points_xz", []):
			points.append(Vector2(p[0], p[1]))
		_add_road(points, float(road.get("width", 3)))
	for key: String in ["ring_road", "lake_loop"]:
		var loop: Dictionary = _layout.data.get(key, {})
		if loop.is_empty():
			continue
		var c := Vector2(loop["center_xz"][0], loop["center_xz"][1])
		var radii := Vector2(loop["radii"][0], loop["radii"][1])
		var points := PackedVector2Array()
		for i in 73:
			var a := TAU * i / 72.0
			points.append(c + Vector2(cos(a) * radii.x, sin(a) * radii.y))
		_add_road(points, float(loop.get("width", 3)))


func _add_road(points: PackedVector2Array, width: float) -> void:
	if points.size() < 2:
		return
	var clear := width * 0.5 + ROAD_CLEAR
	var bounds := Rect2(points[0], Vector2.ZERO)
	for p: Vector2 in points:
		bounds = bounds.expand(p)
	_roads.append({"points": points, "clear": clear, "bounds": bounds.grow(clear)})


## True when (x, z) is further than the clearance from every blueprint road centre line.
func _off_roads(x: float, z: float, extra: float) -> bool:
	var p := Vector2(x, z)
	for road: Dictionary in _roads:
		var bounds: Rect2 = road["bounds"]
		if not bounds.grow(extra).has_point(p):
			continue
		var points: PackedVector2Array = road["points"]
		var limit: float = road["clear"] + extra
		for i in points.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(p, points[i], points[i + 1])
			if q.distance_squared_to(p) < limit * limit:
				return false
	return true


func _add_rect(x: float, z: float, sx: float, sz: float, margin: float) -> void:
	_clear_rects.append(Rect2(x - sx * 0.5 - margin, z - sz * 0.5 - margin, sx + margin * 2.0, sz + margin * 2.0))


func _is_clear(x: float, z: float) -> bool:
	var p := Vector2(x, z)
	for r: Rect2 in _clear_rects:
		if r.has_point(p):
			return false
	for c: Vector3 in _clear_points:
		if Vector2(c.x, c.y).distance_squared_to(p) < c.z * c.z:
			return false
	return true


## True when the ground around the point (radius r) has no road, field, sand or cobble.
func _is_open_ground(x: float, z: float, r: float) -> bool:
	for offset: Vector2 in [Vector2.ZERO, Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
		var c := _sample(_control, x + offset.x, z + offset.y)
		if c.r > 0.12 or c.g > 0.12 or c.b > 0.12 or c.a > 0.12:
			return false
	return true


func _sample(image: Image, x: float, z: float) -> Color:
	var lo := _layout.get_bounds_min()
	var hi := _layout.get_bounds_max()
	var u := clampi(int((x - lo.x) / (hi.x - lo.x) * image.get_width()), 0, image.get_width() - 1)
	var v := clampi(int((z - lo.y) / (hi.y - lo.y) * image.get_height()), 0, image.get_height() - 1)
	return image.get_pixel(u, v)


## Returns {chunk name: {model name: Array[Transform3D]}}.
func _scatter() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var chunks := {}
	var lo := _layout.get_bounds_min() + Vector2.ONE * 3.0
	var hi := _layout.get_bounds_max() - Vector2.ONE * 3.0
	var z := lo.y
	while z < hi.y:
		var x := lo.x
		while x < hi.x:
			# Draw every random number up front so one cell's outcome never shifts the next cell's.
			var px := x + rng.randf() * cell_size
			var pz := z + rng.randf() * cell_size
			var roll := rng.randf()
			var pick := rng.randf()
			var yaw := rng.randf() * TAU
			var scale_roll := rng.randf()
			x += cell_size
			var model := _choose(px, pz, roll, pick)
			if model == "":
				continue
			var kind := kind_of(model)
			var h := terrain.get_height(px, pz)
			var normal := terrain.get_normal(px, pz)
			if kind == "rock":
				if normal.y < MAX_ROCK_SLOPE:
					continue
			elif normal.y < MAX_TREE_SLOPE or h > MAX_TREE_ALTITUDE:
				continue
			var s := lerpf(0.8, 1.25, scale_roll)
			var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s)
			if kind == "rock":
				h -= 0.12 * s * ROCK_SIZE[model]
			var transform := Transform3D(basis, Vector3(px, h, pz))
			var chunk := _layout.chunk_of(transform.origin)
			if not chunks.has(chunk):
				chunks[chunk] = {}
			if not chunks[chunk].has(model):
				chunks[chunk][model] = []
			chunks[chunk][model].append(transform)
			if not placed.has(model):
				placed[model] = PackedVector3Array()
			placed[model].append(transform.origin)
		z += cell_size
	return chunks


## Picks the model for one candidate cell, or "" for nothing.
func _choose(x: float, z: float, roll: float, pick: float) -> String:
	var region: Dictionary = _layout.region_at(Vector3(x, 0, z))
	var densities: Dictionary = DENSITY.get(region.get("id", ""), {})
	if densities.is_empty():
		return ""
	if _layout.is_over_lake(Vector3(x, 0, z)) or not _is_clear(x, z):
		return ""
	var zone := _sample(_zones, x, z)
	var cell_area := cell_size * cell_size / 100.0
	var acc := 0.0
	for kind: String in densities:
		var density: float = densities[kind]
		match kind:
			"pine", "broadleaf":
				density *= lerpf(0.35, 1.0, zone.r)  # thicker on forest floor
			"rock":
				density *= 1.0 + zone.b  # more on rocky ground
		acc += density * cell_area
		if roll < acc:
			var models: Array = KINDS[kind].filter(func(m: String) -> bool: return _meshes.has(m))
			if models.is_empty():
				return ""
			var clearance := 2.5 if kind in ["pine", "broadleaf"] else 1.5
			if not _is_open_ground(x, z, clearance) or not _off_roads(x, z, clearance - 1.5):
				return ""
			return models[mini(int(pick * models.size()), models.size() - 1)]
	return ""


func _build_chunks(chunks: Dictionary) -> void:
	var names := chunks.keys()
	names.sort()
	for chunk_name: String in names:
		var chunk_node := Node3D.new()
		chunk_node.name = "Chunk_%s" % chunk_name
		add_child(chunk_node)
		var body := StaticBody3D.new()
		body.name = "Collision"
		body.collision_layer = WORLD_LAYER
		body.collision_mask = 0
		chunk_node.add_child(body)
		var models: Dictionary = chunks[chunk_name]
		for model: String in models:
			var transforms: Array = models[model]
			var kind := kind_of(model)
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.mesh = _meshes[model]
			multimesh.instance_count = transforms.size()
			for i in transforms.size():
				multimesh.set_instance_transform(i, transforms[i])
			var instance := MultiMeshInstance3D.new()
			instance.name = model
			instance.multimesh = multimesh
			instance.visibility_range_end = VISIBILITY_END[kind]
			if kind == "bush":
				instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			chunk_node.add_child(instance)
			if kind != "bush":
				for t: Transform3D in transforms:
					_add_collider(body, kind, model, t)


func _add_collider(body: StaticBody3D, kind: String, model: String, t: Transform3D) -> void:
	var s := t.basis.get_scale().x
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	if kind == "rock":
		var size: float = ROCK_SIZE[model] * s
		cylinder.radius = size * 0.5
		cylinder.height = size * 0.7
		shape.position = t.origin + Vector3.UP * size * 0.3
	else:
		cylinder.radius = 0.35 * s
		cylinder.height = 4.0 * s
		shape.position = t.origin + Vector3.UP * 2.0 * s
	shape.shape = cylinder
	body.add_child(shape)
