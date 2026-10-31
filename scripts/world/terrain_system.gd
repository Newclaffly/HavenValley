@tool
class_name TerrainSystem
extends Node3D
## The world's ground. Uses Terrain3D when the add-on is installed and its data exists; otherwise
## falls back to the built-in HeightmapTerrain made from heightmap.res. Both use the same heights and
## the same stylized look, so the rest of the game only talks to this node:
##   get_height(x, z), get_normal(x, z), get_backend_name()
##
## Terrain3D is created from code (not saved in world.tscn) so the world scene still opens when the
## add-on is missing. To sculpt, open scenes/world/terrain_editor.tscn, which holds a real Terrain3D
## node pointing at the same data folder.

enum Backend { NONE, TERRAIN3D, HEIGHTMAP }

## Use Terrain3D when it is installed. Turn off to force the built-in terrain (for comparison or tests).
@export var prefer_terrain3d: bool = true

@export_group("Terrain3D")
@export_dir var terrain3d_data_directory: String = "res://resources/world/terrain/terrain3d"
@export var terrain3d_shader: Shader
@export var terrain3d_region_size: int = 256

@export_group("Shared")
## Ground-type map: R dirt road, G tilled soil, B sand / river bed, A cobble.
@export var control_map: Texture2D
## Zone map: R forest floor, G meadow flowers, B mountain rock.
@export var zone_map: Texture2D
@export var show_chunk_grid: bool = false:
	set(value):
		show_chunk_grid = value
		_apply_grid()

@export_group("Built-in fallback")
@export var heightmap: Image
@export var heightmap_shader: Shader

@export_tool_button("Rebuild Terrain", "Reload") var rebuild_button := rebuild

const WORLD_LAYER := 1
const T3D_COLLISION_FULL_GAME := 3  # Terrain3DCollision.CollisionMode.FULL_GAME

var backend: Backend = Backend.NONE
var _terrain3d: Node3D
var _terrain3d_data: Object
var _heightmap_terrain: HeightmapTerrain


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_terrain3d = null
	_terrain3d_data = null
	_heightmap_terrain = null
	backend = Backend.NONE
	if prefer_terrain3d and _can_use_terrain3d():
		_build_terrain3d()
	else:
		_build_heightmap()
	_apply_grid()


## Ground height at x, z. Outside the terrain it returns 0.
func get_height(x: float, z: float) -> float:
	match backend:
		Backend.TERRAIN3D:
			# Terrain3D returns exact heights on its 1 m grid but does not blend smoothly between
			# grid points, so read the four surrounding points and blend them here.
			var x0 := floorf(x)
			var z0 := floorf(z)
			var tx := x - x0
			var tz := z - z0
			var top := lerpf(_t3d_height(x0, z0), _t3d_height(x0 + 1.0, z0), tx)
			var bottom := lerpf(_t3d_height(x0, z0 + 1.0), _t3d_height(x0 + 1.0, z0 + 1.0), tx)
			return lerpf(top, bottom, tz)
		Backend.HEIGHTMAP:
			return _heightmap_terrain.get_height(x, z)
	return 0.0


func _t3d_height(x: float, z: float) -> float:
	var h: float = _terrain3d_data.call("get_height", Vector3(x, 0.0, z))
	return 0.0 if is_nan(h) else h


func get_height_at(world_position: Vector3) -> float:
	return get_height(world_position.x, world_position.z)


func get_normal(x: float, z: float) -> Vector3:
	var dx := get_height(x + 1.0, z) - get_height(x - 1.0, z)
	var dz := get_height(x, z + 1.0) - get_height(x, z - 1.0)
	return Vector3(-dx, 2.0, -dz).normalized()


func get_backend_name() -> String:
	return ["none", "Terrain3D", "built-in heightmap"][backend]


## Point Terrain3D's level of detail and collision at a node (the player). Ignored for the built-in terrain.
func set_focus_target(target: Node3D) -> void:
	if backend == Backend.TERRAIN3D:
		_terrain3d.set("clipmap_target", target)
		_terrain3d.set("collision_target", target)


func _can_use_terrain3d() -> bool:
	if not ClassDB.class_exists("Terrain3D"):
		return false
	var dir := DirAccess.open(terrain3d_data_directory)
	if dir == null:
		return false
	for file in dir.get_files():
		if file.begins_with("terrain3d") and file.ends_with(".res"):
			return true
	return false


func _build_terrain3d() -> void:
	var terrain: Node3D = ClassDB.instantiate("Terrain3D")
	terrain.name = "Terrain3D"
	terrain.set("region_size", terrain3d_region_size)
	var material: Resource = ClassDB.instantiate("Terrain3DMaterial")
	material.set("shader_override_enabled", true)
	material.set("shader_override", terrain3d_shader)
	terrain.set("material", material)
	terrain.set("collision_mode", T3D_COLLISION_FULL_GAME)
	terrain.set("collision_layer", WORLD_LAYER)
	terrain.set("collision_mask", 0)
	# Saving editor textures needs an Assets file; this terrain has no painted textures.
	terrain.set("free_editor_textures", false)
	# Set the data folder before entering the tree, the same order as a Terrain3D loaded from a scene.
	terrain.set("data_directory", terrain3d_data_directory)
	add_child(terrain)
	# Terrain3D turns on its checkerboard debug view when no textures are painted; our shader colours the ground.
	material.set("show_checkered", false)
	material.call("set_shader_param", "control_map", control_map)
	material.call("set_shader_param", "zone_map", zone_map)
	_terrain3d = terrain
	_terrain3d_data = terrain.get("data")
	backend = Backend.TERRAIN3D


func _build_heightmap() -> void:
	var terrain := HeightmapTerrain.new()
	terrain.name = "HeightmapTerrain"
	terrain.heightmap = heightmap
	terrain.control_map = control_map
	terrain.zone_map = zone_map
	terrain.terrain_shader = heightmap_shader
	add_child(terrain)
	_heightmap_terrain = terrain
	backend = Backend.HEIGHTMAP


func _apply_grid() -> void:
	match backend:
		Backend.TERRAIN3D:
			var material: Object = _terrain3d.get("material")
			if material:
				material.call("set_shader_param", "show_chunk_grid", show_chunk_grid)
		Backend.HEIGHTMAP:
			_heightmap_terrain.show_chunk_grid = show_chunk_grid
