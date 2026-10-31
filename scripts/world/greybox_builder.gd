@tool
class_name GreyboxBuilder
extends Node3D
## Builds the greybox stand-ins for everything built on the terrain: building boxes, market stalls,
## village houses, bridges, docks, a readable sign at every landmark, and the world-edge backstop.
##
## Everything is generated from world_layout.json when the scene starts, so the world always matches
## the blueprint. In the editor the same build runs as a preview (not saved into the scene); use the
## "Rebuild Preview" button in the Inspector after editing the JSON or regenerating the terrain.
##
## Heights come from the terrain. Buildings are sized as Phase 2 blockouts; Blender models replace
## them building by building (W5) without changing positions.

@export var layout_json: JSON
## The terrain to stand on. Must be earlier in the scene tree so it is built first.
@export var terrain: TerrainSystem
@export var show_labels: bool = true
@export var build_signs: bool = true
@export_tool_button("Rebuild Preview", "Reload") var rebuild_button := rebuild

const WORLD_LAYER := 1  # Physics layer 1 "world".

# Building box heights in metres (blockout sizes until Blender models replace them).
const BUILDING_HEIGHTS := {
	"town_hall": 12.0, "general_store": 6.0, "cafe": 5.0, "restaurant": 6.0, "blacksmith": 5.0,
	"carpenter": 6.0, "storage_delivery": 5.0, "farmhouse": 7.0, "well": 1.0, "barn": 9.0,
	"coop": 3.0, "storage_bld": 5.0, "greenhouse": 4.0, "old_mill": 8.0, "fisher_cottage": 5.0,
}
# Landmarks that are ground areas (painted into the terrain), not solid boxes.
const AREA_IDS := [
	"public_square", "marketplace", "community_garden", "small_park", "kitchen_garden",
	"pasture", "starter_field", "plot_a", "plot_b", "plot_c",
]
# Landmarks that are water features; they get a marker and sign but no ground pad.
const NO_POST_IDS := ["spawn", "mirror_lake", "res_district"]
const DOCKS := {"lakeside_landing": 14.0, "fishing_pier": 10.0}
const CATEGORY_COLORS := {
	"civic": Color("b8452e"), "shop": Color("d08a2e"), "home": Color("8c6b4f"),
	"plaza": Color("c9b48a"), "farm": Color("7fa24a"), "water": Color("1a7891"),
	"nature": Color("2d6a3b"), "mountain": Color("6a5c80"), "spawn": Color("e2a800"),
}
const AREA_EDGE_COLOR := Color("8a6a3c")
const WOOD_COLOR := Color("7a5634")
const REGION_NAMES := {
	"village": "Haven Village", "farm": "Farm Valley", "forest": "Westwood Forest",
	"mountain": "Ridge Mountains", "lake": "Haven River & Mirror Lake", "meadow": "Meadowlands",
}

var _materials: Dictionary = {}
var _layout: WorldLayout


func _ready() -> void:
	rebuild()


## Delete the generated children and build them again from the JSON.
func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_materials.clear()
	_layout = WorldLayout.from_json(layout_json)
	if not _layout.is_valid():
		push_warning("GreyboxBuilder: assign res://resources/world/world_layout.json to Layout Json.")
		return
	if terrain == null:
		push_warning("GreyboxBuilder: assign the Terrain node.")
		return
	_build_landmarks()
	_build_village_details()
	_build_bridges()
	_build_docks()
	_build_world_edges()


func _height(x: float, z: float) -> float:
	return terrain.get_height(x, z)


func _ground(values: Array) -> Vector3:
	var v := WorldLayout.to_vec3(values)
	return Vector3(v.x, _height(v.x, v.z), v.z)


# --- Landmarks ------------------------------------------------------------------------------------

func _build_landmarks() -> void:
	var root := _group("Landmarks")
	for landmark: Dictionary in _layout.get_landmarks():
		var id: String = landmark.get("id", "")
		var footprint = landmark.get("footprint")
		if id in NO_POST_IDS or DOCKS.has(id):
			_point_marker(root, landmark, false)
		elif footprint is Array and AREA_IDS.has(id):
			_area_landmark(root, landmark, footprint)
		elif footprint is Array:
			_building_landmark(root, landmark, footprint)
		else:
			_point_marker(root, landmark, true)


func _building_landmark(root: Node3D, landmark: Dictionary, footprint: Array) -> void:
	var id: String = landmark["id"]
	var centre := WorldLayout.to_vec3(landmark["position"])
	var size := Vector2(float(footprint[0]), float(footprint[1]))
	var height: float = BUILDING_HEIGHTS.get(id, 6.0)
	var color: Color = CATEGORY_COLORS.get(landmark.get("category", ""), Color.GRAY)
	if landmark.get("category", "") == "water":
		color = WOOD_COLOR  # buildings by the water (mill, fisher's cottage) are timber
	var body := _box_on_ground(root, id, centre.x, centre.z, size, height, color)
	var base_y := body.position.y
	if id == "town_hall":
		# 22 m clock tower over the hall, top 34 m above the plateau: the main navigation landmark.
		_solid_box(body, "ClockTower", Vector3(0, 0, -size.y * 0.25), Vector3(6, 34, 6), color.darkened(0.15))
	_label(root, landmark.get("name", id), Vector3(centre.x, base_y + height + (24.0 if id == "town_hall" else 1.5), centre.z), 64)
	if build_signs:
		var front := _facing_vector(landmark.get("faces", ""))
		var offset := Vector3(front.x * (size.x * 0.5 + 2.0), 0, front.z * (size.y * 0.5 + 2.0))
		_sign(root, landmark, Vector3(centre.x, 0, centre.z) + offset)


func _area_landmark(root: Node3D, landmark: Dictionary, footprint: Array) -> void:
	var id: String = landmark["id"]
	var centre := _ground(landmark["position"])
	# Low fence-post corners mark the area; the ground colour itself is painted into the terrain.
	var half := Vector2(float(footprint[0]), float(footprint[1])) * 0.5
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var p := Vector2(centre.x, centre.z) + half * corner
		_solid_box(root, "%s_corner" % id, Vector3(p.x, _height(p.x, p.y), p.y), Vector3(0.25, 0.9, 0.25), AREA_EDGE_COLOR)
	_label(root, landmark.get("name", id), centre + Vector3.UP * 3.0, 56)
	if build_signs:
		_sign(root, landmark, Vector3(centre.x, 0, centre.z + float(footprint[1]) * 0.5 - 1.0))


func _point_marker(root: Node3D, landmark: Dictionary, with_post: bool) -> void:
	var id: String = landmark["id"]
	var pos := _ground(landmark["position"])
	if DOCKS.has(id):
		pos.y = maxf(pos.y, 1.0)
	if id == "mirror_lake":
		pos.y = 0.0
	var color: Color = CATEGORY_COLORS.get(landmark.get("category", ""), Color.GRAY)
	if with_post:
		var post := MeshInstance3D.new()
		post.name = id
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.5
		cylinder.bottom_radius = 0.6
		cylinder.height = 4.0
		cylinder.material = _material(color)
		post.mesh = cylinder
		post.position = pos + Vector3.UP * 2.0
		root.add_child(post)
	_label(root, landmark.get("name", id), pos + Vector3.UP * 5.5, 56)
	if build_signs and id != "spawn" and id != "mirror_lake" and id != "res_district":
		_sign(root, landmark, Vector3(pos.x, 0, pos.z + 1.5))


func _build_village_details() -> void:
	var root := _group("VillageDetails")
	for house: Dictionary in _layout.data.get("village_houses", []):
		var p := WorldLayout.to_vec3(house["position"])
		var size: Array = house.get("footprint", [8, 8])
		_box_on_ground(root, house.get("id", "House"), p.x, p.z, Vector2(size[0], size[1]), 6.0, CATEGORY_COLORS["home"])
	for stall: Dictionary in _layout.data.get("market_stalls", []):
		var p := WorldLayout.to_vec3(stall["position"])
		var size: Array = stall.get("footprint", [4, 3])
		_box_on_ground(root, stall.get("id", "Stall"), p.x, p.z, Vector2(size[0], size[1]), 2.5, Color("d9a55a"))


# --- Bridges and docks ------------------------------------------------------------------------------

## Each bridge spans between the bank tops on either side of its blueprint centre. The deck slopes
## from one bank top to the other so it meets the ground at both ends without a step.
func _build_bridges() -> void:
	var root := _group("Bridges")
	for bridge: Dictionary in _layout.data.get("bridges", []):
		var centre := WorldLayout.to_vec3(bridge.get("position", [0, 0, 0]))
		var yaw := deg_to_rad(-float(bridge.get("rotation_y_deg", 0)))  # blueprint angles are clockwise on the map
		var axis := Basis(Vector3.UP, yaw) * Vector3.RIGHT
		var width := float(bridge.get("width", 3))
		var min_half := float(bridge.get("span", 10)) * 0.5
		var end_a := _bank_top(centre, -axis, min_half)
		var end_b := _bank_top(centre, axis, min_half)
		# Overlap 1 m into the ground at each end.
		var a := end_a - axis * 1.0
		var b := end_b + axis * 1.0
		a.y = end_a.y
		b.y = end_b.y
		_bridge_deck(root, bridge.get("id", "Bridge"), a, b, width)
		_label(root, "%s %s" % [bridge.get("id", ""), bridge.get("name", "")], (end_a + end_b) * 0.5 + Vector3.UP * 3.0, 40)


## Walk outward from the centre until the ground stops rising (the bank top), at least min_half metres.
func _bank_top(centre: Vector3, direction: Vector3, min_half: float) -> Vector3:
	var best := centre + direction * min_half
	best.y = _height(best.x, best.z)
	var distance := min_half
	while distance < min_half + 12.0:
		distance += 0.5
		var p := centre + direction * distance
		var h := _height(p.x, p.z)
		if h < best.y + 0.02:
			break
		best = Vector3(p.x, h, p.z)
	return best


func _bridge_deck(parent: Node3D, node_name: String, a: Vector3, b: Vector3, width: float) -> void:
	var length := a.distance_to(b)
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	var forward := (b - a).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var up := right.cross(forward).normalized()
	# Box local X runs along the deck.
	body.transform = Transform3D(Basis(forward, up, right), (a + b) * 0.5 - up * 0.2)
	parent.add_child(body)
	_box_child(body, Vector3.ZERO, Vector3(length, 0.4, width), WOOD_COLOR)
	for side in [-1.0, 1.0]:
		_box_child(body, Vector3(0, 0.7, side * (width * 0.5 - 0.08)), Vector3(length - 2.0, 0.12, 0.12), WOOD_COLOR.darkened(0.2))
		_box_child(body, Vector3(0, 0.35, side * (width * 0.5 - 0.08)), Vector3(0.12, 0.7, 0.12), WOOD_COLOR.darkened(0.2))


func _build_docks() -> void:
	var root := _group("Docks")
	var lake: Dictionary = _layout.data.get("water", {}).get("lake", {})
	var centre := WorldLayout.to_vec3(lake.get("center", [0, 0, 0]))
	for id: String in DOCKS:
		var landmark := _layout.get_landmark(id)
		if landmark.is_empty():
			continue
		var tip := WorldLayout.to_vec3(landmark["position"])
		var out := Vector3(tip.x - centre.x, 0, tip.z - centre.z).normalized()  # from lake toward shore
		var length: float = DOCKS[id]
		var shore := tip + out * length
		var deck_y := maxf(1.0, _height(shore.x, shore.z))
		_bridge_deck(root, id, Vector3(tip.x, deck_y, tip.z), Vector3(shore.x, deck_y, shore.z) + out * 1.0, 2.5)


func _build_world_edges() -> void:
	# Invisible walls at the playable edge, behind the terrain's own cliffs and hills.
	var root := _group("WorldEdges")
	var lo := _layout.get_bounds_min()
	var hi := _layout.get_bounds_max()
	var span := hi - lo
	var centre := (hi + lo) * 0.5
	var walls := [
		[Vector3(centre.x, 100, lo.y - 1), Vector3(span.x + 4, 300, 2)],
		[Vector3(centre.x, 100, hi.y + 1), Vector3(span.x + 4, 300, 2)],
		[Vector3(lo.x - 1, 100, centre.y), Vector3(2, 300, span.y + 4)],
		[Vector3(hi.x + 1, 100, centre.y), Vector3(2, 300, span.y + 4)],
	]
	for wall: Array in walls:
		var body := StaticBody3D.new()
		body.collision_layer = WORLD_LAYER
		body.collision_mask = 0
		body.position = wall[0]
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = wall[1]
		shape.shape = box
		body.add_child(shape)
		root.add_child(body)


# --- Helpers ---------------------------------------------------------------------------------------

func _group(group_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = group_name
	add_child(node)
	return node


## A solid box whose base follows the lowest corner of its footprint, sunk 0.5 m so no edge floats.
func _box_on_ground(parent: Node3D, node_name: String, x: float, z: float, size: Vector2, height: float, color: Color) -> StaticBody3D:
	var lowest := INF
	var highest := -INF
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2.ZERO]:
		var h := _height(x + corner.x * size.x * 0.5, z + corner.y * size.y * 0.5)
		lowest = minf(lowest, h)
		highest = maxf(highest, h)
	var base := lowest - 0.5
	var total := height + (highest - lowest) + 0.5
	var body := _solid_box(parent, node_name, Vector3(x, base, z), Vector3(size.x, total, size.y), color)
	return body


func _solid_box(parent: Node3D, node_name: String, base_position: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	body.position = base_position
	_box_child(body, Vector3(0, size.y * 0.5, 0), size, color)
	parent.add_child(body)
	return body


func _box_child(body: Node3D, local_position: Vector3, size: Vector3, color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = _material(color)
	mesh_instance.mesh = box
	mesh_instance.position = local_position
	body.add_child(mesh_instance)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	shape.position = local_position
	body.add_child(shape)


func _label(parent: Node3D, text: String, label_position: Vector3, font_size: int) -> void:
	if not show_labels:
		return
	var label := Label3D.new()
	label.text = text
	label.position = label_position
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = font_size
	label.outline_size = 12
	label.pixel_size = 0.01
	label.modulate = Color(1, 1, 0.96)
	label.outline_modulate = Color(0.12, 0.16, 0.12)
	parent.add_child(label)


func _sign(parent: Node3D, landmark: Dictionary, flat_position: Vector3) -> void:
	var info_sign := InfoSign.new()
	info_sign.name = "Sign_%s" % landmark.get("id", "")
	info_sign.position = Vector3(flat_position.x, _height(flat_position.x, flat_position.z), flat_position.z)
	var pos := WorldLayout.to_vec3(landmark.get("position", [0, 0, 0]))
	info_sign.title = landmark.get("name", "")
	info_sign.message = "%s\nBlueprint position (%d, %d, %d) · chunk %s" % [
		REGION_NAMES.get(landmark.get("region", ""), ""), pos.x, pos.y, pos.z, _layout.chunk_of(pos)]
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.0
	shape.shape = sphere
	shape.position = Vector3(0, 1.0, 0)
	info_sign.add_child(shape)

	# Visible sign post so the player can see what to walk up to.
	var post := MeshInstance3D.new()
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.12, 1.4, 0.12)
	post_mesh.material = _material(Color("5a3d22"))
	post.mesh = post_mesh
	post.position = Vector3(0, 0.7, 0)
	info_sign.add_child(post)
	var board := MeshInstance3D.new()
	var board_mesh := BoxMesh.new()
	board_mesh.size = Vector3(0.9, 0.5, 0.06)
	board_mesh.material = _material(Color("c79a5b"))
	board.mesh = board_mesh
	board.position = Vector3(0, 1.4, 0)
	info_sign.add_child(board)
	parent.add_child(info_sign)


func _facing_vector(faces: String) -> Vector3:
	match faces.substr(0, 1):
		"N":
			return Vector3(0, 0, -1)
		"S":
			return Vector3(0, 0, 1)
		"E":
			return Vector3(1, 0, 0)
		"W":
			return Vector3(-1, 0, 0)
	return Vector3(0, 0, 1)


func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	_materials[key] = material
	return material
