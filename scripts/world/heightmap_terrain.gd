@tool
class_name HeightmapTerrain
extends Node3D
## Built-in terrain made from the generated heightmap (1025 x 1025 samples, 1 m apart, covering
## X/Z -512..512). Builds 8 x 8 mesh tiles and one HeightMapShape3D for collision, and answers
## height queries for placing objects.
##
## This is the terrain the game uses without add-ons. When Terrain3D is installed it can import the
## same heightmap (resources/world/terrain/heightmap.exr) for editor sculpting and painting.

## Godot Image in FORMAT_RF, heights in metres. Built by tools/terrain/build_terrain_resources.gd.
@export var heightmap: Image
## Ground-type map: R dirt road, G tilled soil, B sand / river bed, A cobble.
@export var control_map: Texture2D
## Zone map: R forest floor, G meadow flowers, B mountain rock.
@export var zone_map: Texture2D
@export var terrain_shader: Shader
## World position of sample (0, 0).
@export var origin: Vector2 = Vector2(-512, -512)
## Mesh vertex spacing in metres (1, 2 or 4). Collision always uses every sample.
@export_range(1, 4) var mesh_step: int = 2
## Tiles per side.
@export var tiles: int = 8
@export var show_chunk_grid: bool = false:
	set(value):
		show_chunk_grid = value
		if _material:
			_material.set_shader_parameter("show_chunk_grid", value)
@export_tool_button("Rebuild Terrain", "Reload") var rebuild_button := rebuild

const WORLD_LAYER := 1

var _heights: PackedFloat32Array = PackedFloat32Array()
var _size: int = 0
var _material: ShaderMaterial


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if heightmap == null or heightmap.get_format() != Image.FORMAT_RF:
		push_warning("HeightmapTerrain: assign resources/world/terrain/heightmap.res (32-bit float image).")
		return
	_size = heightmap.get_width()
	_heights = heightmap.get_data().to_float32_array()
	_build_material()
	_build_meshes()
	_build_collision()


## Terrain height at a world position (bilinear). Positions outside the map clamp to the edge.
func get_height(x: float, z: float) -> float:
	if _heights.is_empty():
		return 0.0
	var fx := clampf(x - origin.x, 0.0, _size - 1.001)
	var fz := clampf(z - origin.y, 0.0, _size - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * _size + ix
	var top := lerpf(_heights[i], _heights[i + 1], tx)
	var bottom := lerpf(_heights[i + _size], _heights[i + _size + 1], tx)
	return lerpf(top, bottom, tz)


func get_height_at(world_position: Vector3) -> float:
	return get_height(world_position.x, world_position.z)


## Ground normal at a world position, from neighbouring samples.
func get_normal(x: float, z: float) -> Vector3:
	var dx := get_height(x + 1.0, z) - get_height(x - 1.0, z)
	var dz := get_height(x, z + 1.0) - get_height(x, z - 1.0)
	return Vector3(-dx, 2.0, -dz).normalized()


func get_world_size() -> float:
	return float(_size - 1)


func _sample(ix: int, iz: int) -> float:
	ix = clampi(ix, 0, _size - 1)
	iz = clampi(iz, 0, _size - 1)
	return _heights[iz * _size + ix]


func _build_material() -> void:
	_material = ShaderMaterial.new()
	_material.shader = terrain_shader
	_material.set_shader_parameter("control_map", control_map)
	_material.set_shader_parameter("zone_map", zone_map)
	_material.set_shader_parameter("world_min", origin)
	_material.set_shader_parameter("world_size", float(_size - 1))
	_material.set_shader_parameter("show_chunk_grid", show_chunk_grid)


func _build_meshes() -> void:
	var cells_total := _size - 1
	var tile_cells := cells_total / tiles  # samples per tile side (128 for 1024 / 8)
	var verts_per_side := tile_cells / mesh_step + 1
	for ty in tiles:
		for tx in tiles:
			var vertices := PackedVector3Array()
			var normals := PackedVector3Array()
			var indices := PackedInt32Array()
			vertices.resize(verts_per_side * verts_per_side)
			normals.resize(verts_per_side * verts_per_side)
			var base_x := tx * tile_cells
			var base_z := ty * tile_cells
			var k := 0
			for vz in verts_per_side:
				for vx in verts_per_side:
					var sx := base_x + vx * mesh_step
					var sz := base_z + vz * mesh_step
					vertices[k] = Vector3(origin.x + sx, _sample(sx, sz), origin.y + sz)
					var dx := _sample(sx + mesh_step, sz) - _sample(sx - mesh_step, sz)
					var dz := _sample(sx, sz + mesh_step) - _sample(sx, sz - mesh_step)
					normals[k] = Vector3(-dx, 2.0 * mesh_step, -dz).normalized()
					k += 1
			for vz in verts_per_side - 1:
				for vx in verts_per_side - 1:
					var a := vz * verts_per_side + vx
					var b := a + 1
					var c := a + verts_per_side
					var d := c + 1
					# Counter-clockwise seen from above (Godot front faces).
					indices.append_array([a, b, c, b, d, c])
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_INDEX] = indices
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(0, _material)
			var instance := MeshInstance3D.new()
			instance.name = "Tile_%d_%d" % [tx, ty]
			instance.mesh = mesh
			add_child(instance)


func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	var shape := HeightMapShape3D.new()
	shape.map_width = _size
	shape.map_depth = _size
	shape.map_data = _heights
	var collision := CollisionShape3D.new()
	collision.shape = shape
	# HeightMapShape3D is centred on its node; 1025 samples span 1024 m.
	collision.position = Vector3(origin.x + (_size - 1) * 0.5, 0.0, origin.y + (_size - 1) * 0.5)
	body.add_child(collision)
	add_child(body)
