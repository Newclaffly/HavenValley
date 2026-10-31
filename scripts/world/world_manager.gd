class_name WorldManager
extends Node3D
## Root script of the world scene (not an autoload).
##
## Spawns the player on the terrain at the blueprint spawn point, reports the player's chunk and
## region, and returns the player to dry ground after walking into deep water or falling out of the
## world. Later phases add persistent object IDs and streaming here.

## Where new games start. Defaults to the blueprint spawn when empty.
@export var spawn_marker: Marker3D
## The player spawns facing this landmark id from the blueprint.
@export var spawn_look_at_landmark: String = "town_hall"
## Feet this far below the lake surface count as deep water (the wading shelf is 1.2 m deep).
@export var deep_water_depth: float = 2.0

var layout: WorldLayout
var current_chunk: String = ""
var current_region: String = ""

var _last_safe_position: Vector3
var _safe_timer: float = 0.0

@onready var _player: PlayerController = $Player
@onready var _terrain: TerrainSystem = $Terrain


func _ready() -> void:
	layout = WorldLayout.load_default()
	_terrain.set_focus_target(_player)
	_spawn_player()
	GameManager.enter_gameplay()


func _physics_process(delta: float) -> void:
	if not layout.is_valid():
		return
	var player_position := _player.global_position
	var chunk := layout.chunk_of(player_position)
	if chunk != current_chunk:
		current_chunk = chunk
		EventBus.player_chunk_changed.emit(chunk)
	var region := layout.region_at(player_position)
	var region_id: String = region.get("id", "")
	if region_id != current_region:
		current_region = region_id
		# Regions with "announce": false (the open valley between named places) report an empty name.
		EventBus.region_changed.emit(region_id, region.get("name", "") if region.get("announce", true) else "")
	_check_safety(player_position, delta)


func get_player() -> PlayerController:
	return _player


func get_terrain() -> TerrainSystem:
	return _terrain


## Ground position (terrain height) at x, z.
func ground_at(x: float, z: float) -> Vector3:
	return Vector3(x, _terrain.get_height(x, z), z)


func _spawn_player() -> void:
	var spawn := layout.get_player_spawn()
	if spawn_marker:
		spawn = spawn_marker.global_position
	spawn = ground_at(spawn.x, spawn.z) + Vector3.UP * 0.05
	var look_at_point := spawn + Vector3.FORWARD
	var landmark := layout.get_landmark(spawn_look_at_landmark)
	if not landmark.is_empty():
		look_at_point = WorldLayout.to_vec3(landmark["position"])
	_player.teleport(spawn, look_at_point)
	_last_safe_position = spawn


func _check_safety(player_position: Vector3, delta: float) -> void:
	var in_deep_water := layout.is_over_lake(player_position) and player_position.y < -deep_water_depth
	if in_deep_water or player_position.y < -60.0:
		_player.teleport(_last_safe_position, _last_safe_position + _player.global_basis.z * -1.0)
		var message := "Swimming arrives in Phase 5." if in_deep_water else ""
		EventBus.notification_requested.emit("The water is too deep" if in_deep_water else "Back on solid ground", message)
		return
	_safe_timer -= delta
	if _safe_timer <= 0.0 and _player.is_on_floor() and player_position.y > -1.0:
		_last_safe_position = player_position + Vector3.UP * 0.05
		_safe_timer = 0.5
