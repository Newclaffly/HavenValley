class_name HarvestSystem
extends Node
## Chopping trees and mining rocks placed by WorldObjects, dropping item pickups, and regrowth of
## trees, rocks and forage spots.
##
## Every tree and rock keeps its permanent id, so a felled tree stays a stump (WorldState) until it
## grows back. Until the day cycle exists (Phase 6) regrowth counts seconds of play time.

## Emitted on every tool hit: what was hit and hits left (0 = felled / broken).
signal hit_landed(id: String, kind: String, hits_left: int)

@export var objects: WorldObjects
## Where pickups are added (a y-sorted node in the view).
@export var pickup_parent: Node2D
@export var tree_regrow_seconds: float = 900.0
@export var rock_regrow_seconds: float = 1200.0
@export var forage_regrow_seconds: float = 600.0
## Regrowth waits while the player is closer than this (map pixels).
@export var regrow_clear_distance: float = 48.0

## Hits needed and what drops, by art name.
const YIELDS := {
	"tree_pine": {"hits": 4, "item": &"wood", "min": 3, "max": 4},
	"tree_pine_tall": {"hits": 5, "item": &"wood", "min": 4, "max": 5},
	"tree_oak": {"hits": 5, "item": &"wood", "min": 4, "max": 5},
	"tree_orange": {"hits": 4, "item": &"wood", "min": 2, "max": 3},
	"tree_apple": {"hits": 4, "item": &"wood", "min": 2, "max": 3},
	"tree_lemon": {"hits": 4, "item": &"wood", "min": 2, "max": 3},
	"rock_small": {"hits": 2, "item": &"stone", "min": 1, "max": 2},
	"rock_large": {"hits": 4, "item": &"stone", "min": 3, "max": 5},
}
const TOOL_KINDS := {ItemData.ToolType.AXE: ["tree"], ItemData.ToolType.PICKAXE: ["rock"]}
const NAMES := {
	"tree_pine": "Pine tree", "tree_pine_tall": "Tall pine", "tree_oak": "Oak tree", "tree_orange": "Orange tree",
	"tree_apple": "Apple tree", "tree_lemon": "Lemon tree", "rock_small": "Rock", "rock_large": "Boulder",
}

var _hits: Dictionary = {}  # id -> hits taken
var _rng := RandomNumberGenerator.new()
var _regrow_timer: float = 0.0


func _ready() -> void:
	add_to_group("harvest_system")
	_rng.randomize()


## Call after WorldObjects.build(): applies saved harvests and forage regrow times.
func setup() -> void:
	for spot: ForageSpot in objects.forage_spots.values():
		spot.regrow_seconds = forage_regrow_seconds
	for id: String in WorldState.harvested_ids("nature:"):
		objects.set_harvested(id, true)
	for id: String in WorldState.harvested_ids(ForageSpot.ID_PREFIX):
		var spot: ForageSpot = objects.forage_spots.get(id)
		if spot:
			spot.set_picked(true)


func _process(delta: float) -> void:
	_regrow_timer -= delta
	if _regrow_timer <= 0.0:
		_regrow_timer = 1.0
		regrow_due()


## The tree or rock a tool would hit around a map position, or "".
func find_target(tool: ItemData.ToolType, map_px: Vector2, radius: float) -> String:
	if objects == null or not TOOL_KINDS.has(tool):
		return ""
	return objects.find_harvestable(map_px, radius, TOOL_KINDS[tool])


func describe(id: String) -> String:
	return NAMES.get(objects.harvestables.get(id, {}).get("art", ""), "")


func hits_left(id: String) -> int:
	var art: String = objects.harvestables.get(id, {}).get("art", "")
	return int(YIELDS.get(art, {}).get("hits", 1)) - int(_hits.get(id, 0))


## One tool hit. Returns hits left (0 = felled / broken), or -1 if there is nothing to hit.
func hit(id: String) -> int:
	var info: Dictionary = objects.harvestables.get(id, {})
	if info.is_empty() or info["hidden"]:
		return -1
	_hits[id] = int(_hits.get(id, 0)) + 1
	var left := hits_left(id)
	if left > 0:
		objects.shake(id)
	else:
		_hits.erase(id)
		objects.set_harvested(id, true)
		WorldState.mark_harvested(id, rock_regrow_seconds if info["kind"] == "rock" else tree_regrow_seconds)
		_drop(info)
	hit_landed.emit(id, info["kind"], left)
	return left


## Drop an item on the ground at a map position; it flies to the player when they come near.
func spawn_pickup(item: ItemData, count: int, map_px: Vector2) -> ItemPickup:
	var pickup := ItemPickup.new()
	pickup.item = item
	pickup.count = count
	pickup.map_position = map_px
	pickup_parent.add_child(pickup)
	return pickup


## Restore everything whose regrow time has passed (unless the player stands right there).
func regrow_due() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	for id: String in WorldState.due_for_regrowth():
		var pos := Vector2.INF
		var info: Dictionary = objects.harvestables.get(id, {})
		var spot: ForageSpot = objects.forage_spots.get(id)
		if not info.is_empty():
			pos = info["pos"]
		elif spot:
			pos = spot.position
		else:
			WorldState.clear_harvested(id)
			continue
		if player and player.global_position.distance_to(pos) < regrow_clear_distance:
			continue
		if spot:
			spot.set_picked(false)
		else:
			objects.set_harvested(id, false)
		WorldState.clear_harvested(id)


func _drop(info: Dictionary) -> void:
	var yields: Dictionary = YIELDS.get(info["art"], {})
	var item := ItemRegistry.get_item(yields.get("item", &""))
	if item == null:
		return
	var count := _rng.randi_range(int(yields["min"]), int(yields["max"]))
	var origin: Vector2 = info["pos"]
	for i in count:
		var angle := TAU * i / count + _rng.randf() * 0.6
		spawn_pickup(item, 1, origin + Vector2(cos(angle), sin(angle)) * _rng.randf_range(5.0, 10.0))
