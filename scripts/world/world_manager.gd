class_name WorldManager
extends Node2D
## Root script of the 2D world scene.
##
## Phase P1-2D: draws a greybox version of the blueprint into the Ground TileMapLayer (grass,
## roads, rivers, lake, bridges, building blocks), places a sign at every building, spawns the
## player at the blueprint spawn and reports the player's chunk and region.
## Phase P2-2D replaces the greybox drawing with the generated tile map.

## Tile atlas coordinates in the placeholder tileset (assets/placeholder/tiles.png).
const GRASS := Vector2i(0, 0)
const PATH := Vector2i(1, 0)
const WATER := Vector2i(2, 0)
const WALL := Vector2i(3, 0)
const REGION_NAMES := {
	"village": "Haven Village", "farm": "Farm Valley", "forest": "Westwood Forest",
	"mountain": "Ridge Mountains", "lake": "Mirror Lake", "river": "Haven River", "meadow": "Meadowlands",
}
const AREA_IDS := [
	"public_square", "marketplace", "community_garden", "small_park", "kitchen_garden",
	"pasture", "starter_field", "plot_a", "plot_b", "plot_c", "res_district", "mirror_lake",
]

var layout: WorldLayout
var current_chunk: String = ""
var current_region: String = ""
var build_msec: int = 0

@onready var ground: TileMapLayer = $Ground
@onready var _signs: Node2D = $Signs
@onready var _player: PlayerController = $Player


func _ready() -> void:
	layout = WorldLayout.load_default()
	var start := Time.get_ticks_msec()
	build_greybox()
	build_msec = Time.get_ticks_msec() - start
	_set_camera_limits()
	_spawn_player()
	GameManager.enter_gameplay()


func _physics_process(_delta: float) -> void:
	var metres := WorldLayout.to_metres(_player.global_position)
	var chunk := layout.chunk_of(metres)
	if chunk != current_chunk:
		current_chunk = chunk
		EventBus.player_chunk_changed.emit(chunk)
	var region_id: String = layout.region_at(metres).get("id", "")
	if region_id == "valley":
		region_id = current_region  # open valley between regions keeps the last name
	if region_id != current_region and region_id != "":
		current_region = region_id
		EventBus.region_changed.emit(region_id, REGION_NAMES.get(region_id, ""))


func get_player() -> PlayerController:
	return _player


## Pixel position of a blueprint point (metres).
func pixels(x_metres: float, z_metres: float) -> Vector2:
	return WorldLayout.to_pixels(x_metres, z_metres)


## True if the tile under a pixel position blocks walking.
func is_blocked(position_px: Vector2) -> bool:
	var atlas := ground.get_cell_atlas_coords(ground.local_to_map(position_px))
	return atlas == WATER or atlas == WALL


# --- Greybox map ----------------------------------------------------------------------------------

func build_greybox() -> void:
	ground.clear()
	var n := WorldLayout.MAP_TILES
	for y in n:
		for x in n:
			ground.set_cell(Vector2i(x, y), 0, GRASS)
	_paint_roads()
	_paint_water()
	_paint_bridges()
	_paint_buildings()
	_place_signs()


func _paint_roads() -> void:
	for road: Dictionary in layout.data.get("roads", []):
		_paint_polyline(road.get("points_xz", []), float(road.get("width", 3)), PATH)
	for key: String in ["ring_road", "lake_loop"]:
		var loop: Dictionary = layout.data.get(key, {})
		if loop.is_empty():
			continue
		var points := []
		for i in 73:
			var a := TAU * i / 72.0
			points.append([loop["center_xz"][0] + cos(a) * loop["radii"][0], loop["center_xz"][1] + sin(a) * loop["radii"][1]])
		_paint_polyline(points, float(loop.get("width", 3)), PATH)


func _paint_water() -> void:
	var water: Dictionary = layout.data.get("water", {})
	var widths: Dictionary = water.get("widths", {})
	_paint_polyline(water.get("river_xz", []), float(widths.get("river_lower", 10)), WATER)
	_paint_polyline(water.get("creek_xz", []), float(widths.get("creek", 5)), WATER)
	_paint_polyline(water.get("outflow_xz", []), float(widths.get("outflow", 8)), WATER)
	var lake: Dictionary = water.get("lake", {})
	if not lake.is_empty():
		var c := Vector2(lake["center"][0], lake["center"][2])
		var r := Vector2(lake["radii"][0], lake["radii"][1])
		var island: Dictionary = water.get("island", {})
		var island_c := Vector2(island.get("center_xz", [0, 0])[0], island.get("center_xz", [0, 0])[1])
		var island_r := float(island.get("radius", 0))
		_for_tiles_in_rect(c - r, c + r, func(tile: Vector2i, m: Vector2) -> void:
			if ((m - c) / r).length_squared() <= 1.0 and m.distance_to(island_c) > island_r:
				ground.set_cell(tile, 0, WATER))


func _paint_bridges() -> void:
	for bridge: Dictionary in layout.data.get("bridges", []):
		var centre := Vector2(bridge["position"][0], bridge["position"][2])
		var angle := deg_to_rad(float(bridge.get("rotation_y_deg", 0)))
		var axis := Vector2(cos(angle), sin(angle))
		var half := float(bridge.get("span", 10)) * 0.5 + 4.0
		_paint_polyline([[centre.x - axis.x * half, centre.y - axis.y * half], [centre.x + axis.x * half, centre.y + axis.y * half]],
			maxf(float(bridge.get("width", 3)), 4.0), PATH)


func _paint_buildings() -> void:
	for landmark: Dictionary in layout.get_landmarks():
		var footprint = landmark.get("footprint")
		if footprint is Array and not AREA_IDS.has(landmark.get("id", "")):
			_paint_rect(Vector2(landmark["position"][0], landmark["position"][2]), Vector2(footprint[0], footprint[1]), WALL)
	for house: Dictionary in layout.data.get("village_houses", []):
		var size: Array = house.get("footprint", [8, 8])
		_paint_rect(Vector2(house["position"][0], house["position"][2]), Vector2(size[0], size[1]), WALL)


func _place_signs() -> void:
	for child in _signs.get_children():
		child.queue_free()
	for landmark: Dictionary in layout.get_landmarks():
		var id: String = landmark.get("id", "")
		if id in ["spawn", "mirror_lake", "res_district"]:
			continue
		var p := Vector2(landmark["position"][0], landmark["position"][2])
		var footprint = landmark.get("footprint")
		var front := _facing(landmark.get("faces", "S"))
		var offset := Vector2.ZERO
		if footprint is Array and not AREA_IDS.has(id):
			offset = front * (Vector2(footprint[0], footprint[1]) * 0.5 + Vector2.ONE * 4.0)
		var sign := InfoSign.new()
		sign.name = "Sign_%s" % id
		sign.title = landmark.get("name", id)
		sign.message = "%s · chunk %s" % [REGION_NAMES.get(landmark.get("region", ""), ""), layout.chunk_of(WorldLayout.to_vec3(landmark["position"]))]
		sign.position = pixels(p.x + offset.x, p.y + offset.y)
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 8.0
		shape.shape = circle
		sign.add_child(shape)
		var post := Polygon2D.new()
		post.color = Color("8a6240")
		post.polygon = PackedVector2Array([Vector2(-6, -12), Vector2(6, -12), Vector2(6, -4), Vector2(1, -4), Vector2(1, 2), Vector2(-1, 2), Vector2(-1, -4), Vector2(-6, -4)])
		sign.add_child(post)
		_signs.add_child(sign)


func _paint_polyline(points: Array, width_metres: float, atlas: Vector2i) -> void:
	var radius := maxf(width_metres * 0.5, WorldLayout.METRES_PER_TILE * 0.6)
	for i in points.size() - 1:
		var a := Vector2(points[i][0], points[i][1])
		var b := Vector2(points[i + 1][0], points[i + 1][1])
		var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * radius
		var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * radius
		_for_tiles_in_rect(lo, hi, func(tile: Vector2i, m: Vector2) -> void:
			if Geometry2D.get_closest_point_to_segment(m, a, b).distance_to(m) <= radius:
				ground.set_cell(tile, 0, atlas))


func _paint_rect(centre: Vector2, size: Vector2, atlas: Vector2i) -> void:
	var lo := centre - size * 0.5
	var hi := centre + size * 0.5
	_for_tiles_in_rect(lo, hi, func(tile: Vector2i, m: Vector2) -> void:
		if m.x >= lo.x and m.x <= hi.x and m.y >= lo.y and m.y <= hi.y:
			ground.set_cell(tile, 0, atlas))


## Calls fn(tile, tile_centre_in_metres) for every map tile whose centre may lie in the metre rect.
func _for_tiles_in_rect(lo: Vector2, hi: Vector2, fn: Callable) -> void:
	var t0 := WorldLayout.to_tile(WorldLayout.to_pixels(lo.x, lo.y))
	var t1 := WorldLayout.to_tile(WorldLayout.to_pixels(hi.x, hi.y))
	for y in range(maxi(0, t0.y), mini(WorldLayout.MAP_TILES - 1, t1.y) + 1):
		for x in range(maxi(0, t0.x), mini(WorldLayout.MAP_TILES - 1, t1.x) + 1):
			var m := WorldLayout.to_metres((Vector2(x, y) + Vector2(0.5, 0.5)) * WorldLayout.TILE_PX)
			fn.call(Vector2i(x, y), Vector2(m.x, m.z))


func _facing(faces: String) -> Vector2:
	match faces.substr(0, 1):
		"N":
			return Vector2.UP
		"E":
			return Vector2.RIGHT
		"W":
			return Vector2.LEFT
	return Vector2.DOWN


func _set_camera_limits() -> void:
	var camera := _player.get_node("Camera") as Camera2D
	var size := WorldLayout.map_size_px()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(size.x)
	camera.limit_bottom = int(size.y)


func _spawn_player() -> void:
	var spawn := layout.get_player_spawn()
	_player.teleport(pixels(spawn.x, spawn.z), Vector2.UP)
