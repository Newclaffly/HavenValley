class_name WorldManager
extends Node2D
## Root script of the 2D world scene.
##
## The world has two halves:
##   * Sim (hidden): the flat top-down map in 16 px tiles — collision tiles painted from the
##     blueprint (water, buildings), signs, tree trunks and the player body. All gameplay runs here.
##   * View: the isometric picture of the same world — GroundView (vector ground), island sides and
##     WorldObjects (y-sorted sprites). The player's sprite and the camera follow the body.
## It also spawns the player at the blueprint spawn and reports the player's chunk and region.

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

## Depth of the island's soil sides in view pixels.
const SIDE_DEPTH := 180.0
const SIDE_TOP := Color("a87a50")
const SIDE_BOTTOM := Color("6f4a2e")

var layout: WorldLayout
var current_chunk: String = ""
var current_region: String = ""
var build_msec: int = 0

@onready var ground: TileMapLayer = $Sim/Ground
@onready var _signs: Node2D = $Sim/Signs
@onready var _obstacles: StaticBody2D = $Sim/Obstacles
@onready var _player: PlayerController = $Sim/Player
@onready var ground_view: GroundView = $View/GroundView
@onready var objects: WorldObjects = $View/Objects
@onready var camera: Camera2D = $View/Camera
var player_sprite: CharacterSprite


func _ready() -> void:
	layout = WorldLayout.load_default()
	var start := Time.get_ticks_msec()
	build_greybox()
	ground_view.build(layout)
	_build_island_sides()
	objects.build(layout, ground, _obstacles, _signs)
	build_msec = Time.get_ticks_msec() - start
	_attach_player_view()
	_set_camera_limits()
	_spawn_player()
	GameManager.enter_gameplay()


func _process(_delta: float) -> void:
	_sync_player_view()


func _physics_process(_delta: float) -> void:
	_sync_player_view()
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


## Map pixel position -> isometric view position.
func view_position(map_px: Vector2) -> Vector2:
	return WorldLayout.to_view(map_px)


## Move the player's sprite out of the hidden simulation into the y-sorted view.
func _attach_player_view() -> void:
	_player.input_transform = WorldLayout.screen_to_ground()
	player_sprite = _player.get_node("Sprite") as CharacterSprite
	player_sprite.reparent(objects, false)
	player_sprite.name = "PlayerSprite"
	var old_camera := _player.get_node_or_null("Camera")
	if old_camera:
		old_camera.queue_free()


func _sync_player_view() -> void:
	if player_sprite == null:
		return
	player_sprite.position = view_position(_player.global_position)
	camera.position = player_sprite.position + Vector2(0, -60)


func _build_island_sides() -> void:
	var size := WorldLayout.map_size_px()
	var west := WorldLayout.to_view(Vector2(0, size.y))
	var south := WorldLayout.to_view(size)
	var east := WorldLayout.to_view(Vector2(size.x, 0))
	var sides := $View/IslandSides as Node2D
	for child in sides.get_children():
		child.queue_free()
	for edge: Array in [[west, south, 1.0], [south, east, 0.82]]:
		var a: Vector2 = edge[0]
		var b: Vector2 = edge[1]
		var shade: float = edge[2]
		var poly := Polygon2D.new()
		poly.polygon = PackedVector2Array([a, b, b + Vector2(0, SIDE_DEPTH), a + Vector2(0, SIDE_DEPTH)])
		poly.vertex_colors = PackedColorArray([SIDE_TOP * shade, SIDE_TOP * shade, SIDE_BOTTOM * shade, SIDE_BOTTOM * shade])
		sides.add_child(poly)
		for depth in [0.0, 60.0, 120.0, SIDE_DEPTH]:
			var line := Line2D.new()
			line.points = PackedVector2Array([a + Vector2(0, depth), b + Vector2(0, depth)])
			line.width = 6.0 if depth == 0.0 or depth == SIDE_DEPTH else 3.0
			line.default_color = GroundView.INK if line.width > 4.0 else Color(GroundView.INK, 0.35)
			sides.add_child(line)
	var rim := Line2D.new()
	rim.points = PackedVector2Array([WorldLayout.to_view(Vector2.ZERO), east, south, west])
	rim.closed = true
	rim.width = 5.0
	rim.default_color = GroundView.INK
	sides.add_child(rim)


func _set_camera_limits() -> void:
	var size := WorldLayout.map_size_px()
	var west := WorldLayout.to_view(Vector2(0, size.y))
	var east := WorldLayout.to_view(Vector2(size.x, 0))
	camera.limit_left = int(west.x) - 400
	camera.limit_right = int(east.x) + 400
	camera.limit_top = -400
	camera.limit_bottom = int(WorldLayout.to_view(size).y + SIDE_DEPTH) + 300


func _spawn_player() -> void:
	var spawn := layout.get_player_spawn()
	_player.teleport(pixels(spawn.x, spawn.z), Vector2.UP)
	_sync_player_view()
	camera.reset_smoothing()
