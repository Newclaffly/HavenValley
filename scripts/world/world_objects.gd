class_name WorldObjects
extends Node2D
## Everything that stands up in the isometric view: buildings, signs, trees, bushes, rocks, flowers.
##
## Sprites live here (y-sorted by their ground point). Trees and rocks also get a small collision
## circle in the simulation (top-down) so the player walks around their trunks.
## Placement of nature is deterministic (fixed seed) and only on open grass, away from roads,
## water and buildings.

const AREA_IDS := [
	"public_square", "marketplace", "community_garden", "small_park", "kitchen_garden",
	"pasture", "starter_field", "plot_a", "plot_b", "plot_c", "res_district", "mirror_lake", "well",
]
const VILLAGE_HOUSES := ["house_village_a", "house_village_b", "house_village_c"]
## Chance per open grass tile, by region: [[art names], chance, collides].
const NATURE := {
	"forest": [[["tree_pine", "tree_pine_tall", "tree_oak"], 0.13, true], [["bush_berries", "bush_flowers"], 0.03, false],
		[["rock_small", "rock_large"], 0.01, true], [["flowers_pink", "flowers_blue"], 0.015, false],
		[["forage_mushrooms"], 0.006, false]],
	"mountain": [[["tree_pine", "tree_pine_tall"], 0.10, true], [["rock_small", "rock_large"], 0.05, true]],
	"meadow": [[["flowers_yellow", "flowers_pink", "flowers_blue"], 0.05, false], [["bush_flowers"], 0.01, false],
		[["tree_oak", "tree_apple"], 0.008, true], [["rock_small"], 0.004, true]],
	"valley": [[["tree_orange", "tree_apple", "tree_oak", "tree_lemon"], 0.03, true], [["bush_flowers", "bush_berries"], 0.02, false],
		[["flowers_pink", "flowers_yellow"], 0.03, false], [["rock_small"], 0.006, true]],
	"river": [[["tree_oak", "tree_apple"], 0.03, true], [["bush_berries"], 0.02, false], [["flowers_blue"], 0.03, false]],
	"lake": [[["tree_oak", "tree_lemon"], 0.025, true], [["flowers_blue", "flowers_pink"], 0.03, false]],
	"village": [[["flowers_pink", "flowers_yellow"], 0.02, false], [["bush_flowers"], 0.006, false]],
	"farm": [[["flowers_yellow"], 0.006, false]],
}
const TRUNK_RADIUS := 3.0  # map pixels (about 0.6 m)
## Things the player can pick by hand: art -> [item id, art shown once picked ("" = hidden)].
const FORAGE := {
	"bush_berries": [&"wild_berries", "bush_leaves"],
	"forage_mushrooms": [&"mushroom", ""],
	"flowers_yellow": [&"wildflower", ""],
}
const GRID := 64.0  # map pixels per lookup cell

@export var random_seed: int = 31102026

var counts: Dictionary = {}  # art name -> count
## Map-pixel positions of everything that collides (trees, rocks), for tests.
var obstacle_positions: PackedVector2Array = PackedVector2Array()
## Trees and rocks by permanent id ("nature:<tile x>_<tile y>"):
## {"art", "kind" ("tree"/"rock"), "pos" (map px), "sprite", "shape", "hidden"}
var harvestables: Dictionary = {}
## Hand-pickable spots by id ("forage:<tile x>_<tile y>") -> ForageSpot.
var forage_spots: Dictionary = {}
var _grid: Dictionary = {}  # Vector2i -> PackedStringArray of harvestable ids


func build(layout: WorldLayout, ground: TileMapLayer, obstacles: StaticBody2D, signs: Node2D, forage_parent: Node2D = null) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	counts.clear()
	obstacle_positions.clear()
	harvestables.clear()
	_grid.clear()
	forage_spots.clear()
	_forage_parent = forage_parent
	if forage_parent:
		for child in forage_parent.get_children():
			forage_parent.remove_child(child)
			child.queue_free()
	for child in obstacles.get_children():
		obstacles.remove_child(child)
		child.queue_free()
	_buildings(layout)
	_signs(signs)
	_nature(layout, ground, obstacles, signs)


var _forage_parent: Node2D


## The id of the nearest visible tree/rock of the given kinds within `radius` map pixels, or "".
func find_harvestable(map_px: Vector2, radius: float, kinds: Array) -> String:
	var best := ""
	var best_d := radius * radius
	var c0 := _cell_of(map_px - Vector2.ONE * radius)
	var c1 := _cell_of(map_px + Vector2.ONE * radius)
	for cx in range(c0.x, c1.x + 1):
		for cy in range(c0.y, c1.y + 1):
			for id: String in _grid.get(Vector2i(cx, cy), PackedStringArray()):
				var info: Dictionary = harvestables[id]
				if info["hidden"] or not kinds.has(info["kind"]):
					continue
				var d: float = (info["pos"] as Vector2).distance_squared_to(map_px)
				if d < best_d:
					best_d = d
					best = id
	return best


## Felled/mined (true) or grown back (false). Trees leave a stump; rocks disappear.
func set_harvested(id: String, harvested: bool) -> void:
	var info: Dictionary = harvestables.get(id, {})
	if info.is_empty() or info["hidden"] == harvested:
		return
	info["hidden"] = harvested
	var sprite: Sprite2D = info["sprite"]
	var art: String = info["art"]
	if info["kind"] == "tree":
		art = ("stump_pine" if art.begins_with("tree_pine") else "stump") if harvested else art
		sprite.texture = load(ArtLibrary.ART_DIR.path_join(art + ".png"))
		sprite.offset = -ArtLibrary.anchor(art)
		sprite.rotation = 0.0
	else:
		sprite.visible = not harvested
	var shape: CollisionShape2D = info["shape"]
	shape.set_deferred("disabled", harvested)


## Wobble a tree or rock (tool hit feedback).
func shake(id: String) -> void:
	var info: Dictionary = harvestables.get(id, {})
	if info.is_empty() or info["hidden"]:
		return
	var sprite: Sprite2D = info["sprite"]
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "rotation", 0.06, 0.05)
	tween.tween_property(sprite, "rotation", -0.05, 0.08)
	tween.tween_property(sprite, "rotation", 0.0, 0.1)


func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / GRID), floori(p.y / GRID))


## Add a sprite at a map-pixel position.
func place(art_name: String, map_px: Vector2) -> Sprite2D:
	var sprite := ArtLibrary.make_sprite(art_name)
	if sprite == null:
		return null
	sprite.position = WorldLayout.to_view(map_px)
	add_child(sprite)
	counts[art_name] = counts.get(art_name, 0) + 1
	return sprite


func _buildings(layout: WorldLayout) -> void:
	for landmark: Dictionary in layout.get_landmarks():
		var id: String = landmark.get("id", "")
		if not landmark.get("footprint") is Array or id in AREA_IDS:
			continue
		var p := WorldLayout.to_vec3(landmark["position"])
		var sprite := place("house_" + id, WorldLayout.to_pixels(p.x, p.z))
		if sprite:
			sprite.name = "Building_" + id
	var houses: Array = layout.data.get("village_houses", [])
	for i in houses.size():
		var p := WorldLayout.to_vec3(houses[i]["position"])
		var sprite := place(VILLAGE_HOUSES[i % VILLAGE_HOUSES.size()], WorldLayout.to_pixels(p.x, p.z))
		if sprite:
			sprite.name = "House_%d" % i


func _signs(signs: Node2D) -> void:
	for sign: Node2D in signs.get_children():
		var sprite := place("sign", sign.position)
		if sprite:
			sprite.name = "SignArt_" + String(sign.name).trim_prefix("Sign_")


func _nature(layout: WorldLayout, ground: TileMapLayer, obstacles: StaticBody2D, signs: Node2D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var keep_clear := PackedVector2Array()
	for sign: Node2D in signs.get_children():
		keep_clear.append(sign.position)
	var spawn := layout.get_player_spawn()
	keep_clear.append(WorldLayout.to_pixels(spawn.x, spawn.z))
	# Plazas and fields are drawn on the ground but are not blocked in the simulation.
	var paved: Array[Rect2] = []
	for landmark: Dictionary in layout.get_landmarks():
		if landmark.get("id", "") in GroundView.PLAZA_IDS + GroundView.FIELD_IDS and landmark.get("footprint") is Array:
			var c := WorldLayout.to_vec3(landmark["position"])
			var size := Vector2(landmark["footprint"][0], landmark["footprint"][1]) + Vector2.ONE * 4.0
			var a := WorldLayout.to_pixels(c.x - size.x * 0.5, c.z - size.y * 0.5)
			paved.append(Rect2(a, size * WorldLayout.PX_PER_METRE))
	var n := WorldLayout.MAP_TILES
	for ty in range(1, n - 1):
		for tx in range(1, n - 1):
			var roll := rng.randf()
			var pick := rng.randf()
			var jitter := Vector2(rng.randf(), rng.randf())
			var cell := Vector2i(tx, ty)
			if ground.get_cell_atlas_coords(cell) != WorldManager.GRASS:
				continue
			var centre := (Vector2(cell) + jitter) * WorldLayout.TILE_PX
			if paved.any(func(r: Rect2) -> bool: return r.has_point(centre)):
				continue
			var region: String = layout.region_at(WorldLayout.to_metres(centre)).get("id", "")
			var acc := 0.0
			for entry: Array in NATURE.get(region, []):
				acc += float(entry[1])
				if roll >= acc:
					continue
				var collides: bool = entry[2]
				if collides and not _open_around(ground, cell, 1):
					break
				if _near(keep_clear, centre, 28.0):
					break
				var names: Array = entry[0]
				var art: String = names[mini(int(pick * names.size()), names.size() - 1)]
				var sprite := place(art, centre)
				if sprite and collides:
					var shape := CollisionShape2D.new()
					var circle := CircleShape2D.new()
					circle.radius = TRUNK_RADIUS * (2.0 if art.begins_with("rock_large") else 1.0)
					shape.shape = circle
					shape.position = centre
					obstacles.add_child(shape)
					obstacle_positions.append(centre)
					var id := "nature:%d_%d" % [tx, ty]
					harvestables[id] = {"art": art, "kind": "rock" if art.begins_with("rock") else "tree", "pos": centre,
						"sprite": sprite, "shape": shape, "hidden": false}
					var grid_cell := _cell_of(centre)
					if not _grid.has(grid_cell):
						_grid[grid_cell] = PackedStringArray()
					_grid[grid_cell].append(id)
				elif sprite and FORAGE.has(art) and _forage_parent and (art != "flowers_yellow" or region == "meadow"):
					_add_forage("forage:%d_%d" % [tx, ty], art, sprite, centre)
				break


func _add_forage(id: String, art: String, sprite: Sprite2D, map_px: Vector2) -> void:
	var spot := ForageSpot.new()
	spot.name = id.replace(":", "_")
	spot.forage_id = id
	spot.item = ItemRegistry.get_item(FORAGE[art][0])
	spot.sprite = sprite
	spot.full_art = art
	spot.picked_art = FORAGE[art][1]
	spot.position = map_px
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 6.0
	shape.shape = circle
	spot.add_child(shape)
	_forage_parent.add_child(spot)
	forage_spots[id] = spot


func _open_around(ground: TileMapLayer, cell: Vector2i, radius: int) -> bool:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if ground.get_cell_atlas_coords(cell + Vector2i(dx, dy)) != WorldManager.GRASS:
				return false
	return true


func _near(points: PackedVector2Array, p: Vector2, distance: float) -> bool:
	for q: Vector2 in points:
		if q.distance_squared_to(p) < distance * distance:
			return true
	return false
