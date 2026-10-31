extends Node
## Automated Phase 2C check: Blender blockouts are placed on the blueprint and nature is scattered
## without blocking roads, buildings or water.
##
##   godot --headless --path . res://tests/phase2c_test.tscn --fixed-fps 60
##
## Or open tests/phase2c_test.tscn and press F6. Exit code 0 when every check passes.

const WORLD_SCENE := "res://scenes/world/world.tscn"
const BUILDING_IDS := ["town_hall", "general_store", "cafe", "restaurant", "blacksmith", "carpenter", "storage_delivery",
	"farmhouse", "well", "barn", "coop", "storage_bld", "greenhouse", "old_mill", "fisher_cottage"]
const VARIANT_IDS := ["house_a", "house_b", "house_c", "stall_a", "stall_b", "stall_c"]
const NATURE_IDS := ["tree_pine_a", "tree_pine_b", "tree_pine_c", "tree_oak_a", "tree_oak_b", "tree_birch_a",
	"bush_a", "bush_b", "rock_a", "rock_b", "rock_c"]
const OVERHANG := 0.9  # roof eaves may reach this far past the sides and back of the footprint
const FRONT_OVERHANG := 3.0  # porches, awnings, steps and loading platforms may reach this far forward

var _passed: int = 0
var _failed: int = 0
var world: WorldManager
var greybox: GreyboxBuilder
var nature: NatureScatter


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	print("--- Haven Valley Phase 2C test (Godot %s) ---" % Engine.get_version_info().string)

	# Assets exist and import
	var missing := PackedStringArray()
	for id: String in BUILDING_IDS + VARIANT_IDS:
		if not _loads("res://assets/buildings/blockout/%s.glb" % id):
			missing.append(id)
	for id: String in NATURE_IDS:
		if not _loads("res://assets/environment/nature/%s.glb" % id):
			missing.append(id)
	_check("all 32 Blender blockouts import", missing.is_empty(), ", ".join(missing))

	world = (load(WORLD_SCENE) as PackedScene).instantiate() as WorldManager
	add_child(world)
	await _physics_frames(10)
	greybox = world.get_node("Greybox")
	nature = world.get_node("Nature")
	var terrain := world.get_terrain()
	var layout := world.layout
	print("  terrain backend: %s, nature built in %d ms" % [terrain.get_backend_name(), nature.build_msec])

	# Buildings use the models, fit their footprints, have collision and cover the slope.
	var landmark_root := greybox.get_node("Landmarks")
	var not_model := PackedStringArray()
	var misfit := PackedStringArray()
	var no_collision := PackedStringArray()
	var exposed := PackedStringArray()
	var wrong_facing := PackedStringArray()
	for id: String in BUILDING_IDS:
		var landmark := layout.get_landmark(id)
		var node := landmark_root.get_node_or_null(id) as Node3D
		if node == null or not greybox.placed_models.has(id):
			not_model.append(id)
			continue
		var footprint: Array = landmark["footprint"]
		var centre := WorldLayout.to_vec3(landmark["position"])
		var fit := _footprint_fit(node, centre, Vector2(footprint[0], footprint[1]), _facing(landmark.get("faces", "S")))
		if fit != "":
			misfit.append("%s %s" % [id, fit])
		if _find_body(node) == null:
			no_collision.append(id)
		var drop := _drop_under(terrain, centre, Vector2(footprint[0], footprint[1]), node.position.y)
		if drop > GreyboxBuilder.PLINTH_DEPTH - 0.2:
			exposed.append("%s %.1f m" % [id, drop])
		var front := node.global_basis.z.normalized()
		var expected := _facing(landmark.get("faces", "S"))
		if front.dot(expected) < 0.99:
			wrong_facing.append(id)
	_check("all 15 buildings use their Blender model", not_model.is_empty(), ", ".join(not_model))
	_check("every model fits its footprint (eaves ≤ %.1f m, front ≤ %.1f m)" % [OVERHANG, FRONT_OVERHANG], misfit.is_empty(), "; ".join(misfit))
	_check("every building has collision", no_collision.is_empty(), ", ".join(no_collision))
	_check("plinths reach the ground on every side", exposed.is_empty(), ", ".join(exposed))
	_check("every building faces its blueprint direction", wrong_facing.is_empty(), ", ".join(wrong_facing))
	var details := greybox.get_node("VillageDetails")
	var detail_models := 0
	for child in details.get_children():
		if greybox.placed_models.has(String(child.name)):
			detail_models += 1
	_check("12 village houses and 8 market stalls use models", detail_models == 20, str(detail_models))

	# A wall really blocks: a ray at chest height into the Town Hall front hits it.
	var hall := WorldLayout.to_vec3(layout.get_landmark("town_hall")["position"])
	var floor_y: float = (landmark_root.get_node("town_hall") as Node3D).position.y
	var hit := _ray(Vector3(hall.x + 8.0, floor_y + 1.5, hall.z + 15.0), Vector3(hall.x + 8.0, floor_y + 1.5, hall.z))
	# The hall wall stands 3 m behind the front of the footprint, behind the portico.
	_check("Town Hall front wall blocks at chest height", not hit.is_empty() and absf(hit["position"].z - (hall.z + 6.0)) < 0.5,
		str(hit.get("position", "no hit")))

	# Nature: amounts per kind and region
	var trees := nature.count("pine") + nature.count("broadleaf")
	print("  scatter: %d pines, %d broadleaf, %d bushes, %d rocks" % [nature.count("pine"), nature.count("broadleaf"),
		nature.count("bush"), nature.count("rock")])
	_check("Westwood Forest is a forest (≥ 1500 trees)", _count_in(layout, "forest", ["pine", "broadleaf"]) >= 1500,
		str(_count_in(layout, "forest", ["pine", "broadleaf"])))
	_check("mountains have pines and rocks", _count_in(layout, "mountain", ["pine"]) >= 150 and _count_in(layout, "mountain", ["rock"]) >= 150,
		"%d pines, %d rocks" % [_count_in(layout, "mountain", ["pine"]), _count_in(layout, "mountain", ["rock"])])
	_check("meadows stay open (scattered trees, some bushes)", _count_in(layout, "meadow", ["pine", "broadleaf"]) < 150 and _count_in(layout, "meadow", ["bush"]) > 50,
		"%d trees, %d bushes" % [_count_in(layout, "meadow", ["pine", "broadleaf"]), _count_in(layout, "meadow", ["bush"])])
	_check("no trees inside the village or on the farm", _count_in(layout, "village", []) == 0 and _count_in(layout, "farm", []) == 0)
	_check("total trees within budget (2000–8000)", trees >= 2000 and trees <= 8000, str(trees))

	# Nature keeps out of roads, water, buildings and spawn.
	var on_road := 0
	var in_water := 0
	var near_building := 0
	var spawn := layout.get_player_spawn()
	var near_spawn := 0
	var rects: Array[Rect2] = []
	for landmark: Dictionary in layout.get_landmarks():
		if landmark.get("footprint") is Array and landmark["id"] != "mirror_lake":
			var p := WorldLayout.to_vec3(landmark["position"])
			rects.append(Rect2(p.x - landmark["footprint"][0] * 0.5 - 2.0, p.z - landmark["footprint"][1] * 0.5 - 2.0,
				landmark["footprint"][0] + 4.0, landmark["footprint"][1] + 4.0))
	for model: String in nature.placed:
		for p: Vector3 in nature.placed[model]:
			var c := nature.control_at(p.x, p.z)
			if c.x > 0.12 or c.y > 0.12 or c.w > 0.12:
				on_road += 1
			if c.z > 0.12 or layout.is_over_lake(p):
				in_water += 1
			for r: Rect2 in rects:
				if r.has_point(Vector2(p.x, p.z)):
					near_building += 1
					break
			if Vector2(p.x - spawn.x, p.z - spawn.z).length() < 12.0:
				near_spawn += 1
	_check("nothing scattered on roads, fields or cobbles", on_road == 0, str(on_road))
	_check("nothing scattered in water or on river sand", in_water == 0, str(in_water))
	_check("nothing scattered within 2 m of a building or area", near_building == 0, str(near_building))
	_check("player spawn is clear", near_spawn == 0, str(near_spawn))

	# Tree trunks block the player.
	var pine: Vector3 = nature.placed.get("tree_pine_a", PackedVector3Array([Vector3.ZERO]))[0]
	var trunk_hit := _ray(pine + Vector3(-3, 1.0, 0), pine + Vector3(3, 1.0, 0))
	_check("tree trunks have collision", not trunk_hit.is_empty() and Vector2(trunk_hit["position"].x - pine.x, trunk_hit["position"].z - pine.z).length() < 0.6,
		str(trunk_hit.get("position", "no hit")) + " tree " + str(pine))

	# Same seed, same forest.
	var before := nature.count()
	var first := nature.placed["tree_oak_a"][0] as Vector3
	nature.rebuild()
	_check("scatter is deterministic", nature.count() == before and (nature.placed["tree_oak_a"][0] as Vector3).is_equal_approx(first))
	_check("scatter builds in under 4 s", nature.build_msec < 4000, "%d ms" % nature.build_msec)

	print("--- %d passed, %d failed ---" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _loads(path: String) -> bool:
	return ResourceLoader.exists(path) and load(path) is PackedScene


func _count_in(layout: WorldLayout, region: String, kinds: Array) -> int:
	var total := 0
	for model: String in nature.placed:
		if not kinds.is_empty() and not kinds.has(NatureScatter.kind_of(model)):
			continue
		for p: Vector3 in nature.placed[model]:
			if layout.region_at(p).get("id", "") == region:
				total += 1
	return total


## "" if the model's horizontal extent matches the footprint, otherwise a description of the error.
func _footprint_fit(node: Node3D, centre: Vector3, footprint: Vector2, front: Vector3) -> String:
	var aabb := _world_aabb(node)
	var lo := Vector2(centre.x - footprint.x * 0.5, centre.z - footprint.y * 0.5)
	var hi := Vector2(centre.x + footprint.x * 0.5, centre.z + footprint.y * 0.5)
	# Overhang past each side: west, east, north, south.
	var sides := {Vector3.LEFT: lo.x - aabb.position.x, Vector3.RIGHT: aabb.end.x - hi.x,
		Vector3.FORWARD: lo.y - aabb.position.z, Vector3.BACK: aabb.end.z - hi.y}
	for side: Vector3 in sides:
		var allowed := FRONT_OVERHANG if side.dot(front) > 0.9 else OVERHANG
		if sides[side] > allowed:
			return "overhangs %.2f m on the %s side" % [sides[side], str(side)]
	var inside := Rect2(lo, hi - lo).intersection(Rect2(aabb.position.x, aabb.position.z, aabb.size.x, aabb.size.z))
	var cover := inside.get_area() / (footprint.x * footprint.y)
	if cover < 0.7:
		return "covers only %d%%" % int(cover * 100)
	return ""


func _world_aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for mesh_instance: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var box := mesh_instance.global_transform * mesh_instance.get_aabb()
		result = box if first else result.merge(box)
		first = false
	if node is MeshInstance3D:
		var own := (node as MeshInstance3D).global_transform * (node as MeshInstance3D).get_aabb()
		result = own if first else result.merge(own)
	return result


func _find_body(node: Node) -> StaticBody3D:
	var bodies := node.find_children("*", "StaticBody3D", true, false)
	return bodies[0] if not bodies.is_empty() else null


## Largest drop from the floor (origin) to the ground under the footprint, sampled every 1 m.
func _drop_under(terrain: TerrainSystem, centre: Vector3, footprint: Vector2, floor_y: float) -> float:
	var worst := 0.0
	var x := -footprint.x * 0.5
	while x <= footprint.x * 0.5 + 0.01:
		var z := -footprint.y * 0.5
		while z <= footprint.y * 0.5 + 0.01:
			worst = maxf(worst, floor_y - terrain.get_height(centre.x + x, centre.z + z))
			z += 1.0
		x += 1.0
	return worst


func _facing(faces: String) -> Vector3:
	return Basis(Vector3.UP, GreyboxBuilder.facing_yaw(faces)) * Vector3.BACK


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	return world.get_world_3d().direct_space_state.intersect_ray(query)


func _physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s  [%s]" % [label, detail])
