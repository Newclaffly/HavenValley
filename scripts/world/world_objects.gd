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
		[["rock_small", "rock_large"], 0.01, true], [["flowers_pink", "flowers_blue"], 0.015, false]],
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

@export var random_seed: int = 31102026

var counts: Dictionary = {}  # art name -> count
## Map-pixel positions of everything that collides (trees, rocks), for tests.
var obstacle_positions: PackedVector2Array = PackedVector2Array()


func build(layout: WorldLayout, ground: TileMapLayer, obstacles: StaticBody2D, signs: Node2D) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	counts.clear()
	obstacle_positions.clear()
	for child in obstacles.get_children():
		obstacles.remove_child(child)
		child.queue_free()
	_buildings(layout)
	_signs(signs)
	_nature(layout, ground, obstacles, signs)


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
				break


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
