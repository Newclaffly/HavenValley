@tool
class_name WorldLayout
extends RefCounted
## Read-only access to the world blueprint in res://resources/world/world_layout.json.
##
## The JSON is the single source of truth for coordinates. Godot imports .json files as JSON
## resources, so they are exported with the game like any other resource.
## Blueprint axes: +X east, −Z north (Y is height), 1 unit = 1 metre, origin at the Town Hall area.
##
## The 2D game draws the blueprint as a 320 × 320 tile map: one tile = 3.125 blueprint metres,
## one tile = 16 pixels, north at the top of the screen. Use to_pixels() / to_metres() / to_tile().

const DEFAULT_PATH := "res://resources/world/world_layout.json"
const COLUMNS := "ABCDEFGH"
const TILE_PX := 16
const MAP_TILES := 320
const METRES_PER_TILE := 3.125
## Pixels per blueprint metre (16 / 3.125).
const PX_PER_METRE := TILE_PX / METRES_PER_TILE
const ORIGIN_METRES := Vector2(-500, -500)


## Blueprint metres (x east, z south) -> 2D world pixels (top-left of the map is 0, 0).
static func to_pixels(x_metres: float, z_metres: float) -> Vector2:
	return (Vector2(x_metres, z_metres) - ORIGIN_METRES) * PX_PER_METRE


## 2D world pixels -> blueprint metres as Vector3(x, 0, z), for region and chunk lookups.
static func to_metres(pixels: Vector2) -> Vector3:
	var m := pixels / PX_PER_METRE + ORIGIN_METRES
	return Vector3(m.x, 0.0, m.y)


## 2D world pixels -> map tile coordinates.
static func to_tile(pixels: Vector2) -> Vector2i:
	return Vector2i(floori(pixels.x / TILE_PX), floori(pixels.y / TILE_PX))


## Size of the whole map in pixels.
static func map_size_px() -> Vector2:
	return Vector2(MAP_TILES, MAP_TILES) * TILE_PX


# --- Isometric view -------------------------------------------------------------------------------
# The simulation (collision, movement, interaction) runs on the flat top-down map above.
# The isometric view draws it with 128 x 64 px diamond tiles: view = ISO * map pixels.

const ISO_TILE := Vector2(128, 64)


## Map pixels (top-down) -> isometric view pixels.
static func iso_transform() -> Transform2D:
	var sx := ISO_TILE.x * 0.5 / TILE_PX
	var sy := ISO_TILE.y * 0.5 / TILE_PX
	return Transform2D(Vector2(sx, sy), Vector2(-sx, sy), Vector2.ZERO)


static func to_view(map_px: Vector2) -> Vector2:
	return iso_transform() * map_px


## Screen direction -> ground (map) direction, for movement input.
static func screen_to_ground() -> Transform2D:
	var t := iso_transform().affine_inverse()
	return Transform2D(t.x, t.y, Vector2.ZERO)

var data: Dictionary = {}


static func load_default() -> WorldLayout:
	return load_from(DEFAULT_PATH)


static func load_from(path: String) -> WorldLayout:
	var layout := WorldLayout.new()
	var resource := load(path) as JSON
	if resource == null or typeof(resource.data) != TYPE_DICTIONARY:
		push_error("WorldLayout: could not read %s" % path)
		return layout
	layout.data = resource.data
	return layout


static func from_json(json: JSON) -> WorldLayout:
	var layout := WorldLayout.new()
	if json and typeof(json.data) == TYPE_DICTIONARY:
		layout.data = json.data
	return layout


func is_valid() -> bool:
	return not data.is_empty()


func get_bounds_min() -> Vector2:
	return _vec2(data.get("bounds", {}).get("min", [-500, -500]))


func get_bounds_max() -> Vector2:
	return _vec2(data.get("bounds", {}).get("max", [500, 500]))


func get_chunk_size() -> float:
	return float(data.get("chunk_size", 125))


func get_player_spawn() -> Vector3:
	return to_vec3(data.get("player_spawn", [0, 0, 0]))


func get_landmarks() -> Array:
	return data.get("landmarks", [])


func get_landmark(id: String) -> Dictionary:
	for landmark: Dictionary in get_landmarks():
		if landmark.get("id") == id:
			return landmark
	return {}


## Chunk name such as "D4" for a world position. Columns A–H run west to east, rows 1–8 north to south.
func chunk_of(world_position: Vector3) -> String:
	var bounds_min := get_bounds_min()
	var size := get_chunk_size()
	var count := int(round((get_bounds_max().x - bounds_min.x) / size))
	var col := clampi(int(floor((world_position.x - bounds_min.x) / size)), 0, count - 1)
	var row := clampi(int(floor((world_position.z - bounds_min.y) / size)), 0, count - 1)
	return "%s%d" % [COLUMNS[col], row + 1]


## The region at a world position: the highest-priority region shape that contains it.
## Returns the region dictionary from the JSON ({"id", "name", "name_th", ...}) or {} if none.
func region_at(world_position: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_priority := -INF
	var p := Vector2(world_position.x, world_position.z)
	for region: Dictionary in data.get("regions", []):
		var priority := float(region.get("priority", 0))
		if priority <= best_priority:
			continue
		var inside := false
		match region.get("shape", ""):
			"rect":
				var r: Array = region.get("rect_xz", [0, 0, 0, 0])
				inside = Rect2(r[0], r[1], r[2], r[3]).has_point(p)
			"ellipse":
				var c := _vec2(region.get("center_xz", [0, 0]))
				var radii := _vec2(region.get("radii", [1, 1]))
				inside = ((p - c) / radii).length_squared() <= 1.0
		if inside:
			best = region
			best_priority = priority
	return best


## True if the position is over Mirror Lake (inside the shoreline ellipse).
func is_over_lake(world_position: Vector3) -> bool:
	var lake: Dictionary = data.get("water", {}).get("lake", {})
	if lake.is_empty():
		return false
	var c := to_vec3(lake["center"])
	var radii := _vec2(lake["radii"])
	var d := Vector2(world_position.x - c.x, world_position.z - c.z) / radii
	return d.length_squared() < 1.0


static func to_vec3(values: Array) -> Vector3:
	if values.size() < 3:
		return Vector3.ZERO
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


static func _vec2(values: Array) -> Vector2:
	if values.size() < 2:
		return Vector2.ZERO
	return Vector2(float(values[0]), float(values[1]))
