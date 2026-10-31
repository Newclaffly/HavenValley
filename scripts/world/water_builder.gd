@tool
class_name WaterBuilder
extends Node3D
## Builds the water surfaces from the blueprint: Haven River, Willow Creek and the lake outflow as
## ribbons that follow their surface heights (steep sections become waterfalls), and Mirror Lake.
##
## The terrain generator carves channels for the same profiles, so the water edge meets the banks.
## Water has no collision in Phase 2: rivers are shallow enough to wade. WorldManager returns the
## player to dry ground if they walk into deep lake water (swimming arrives in Phase 5).

@export var layout_json: JSON
@export var water_shader: Shader
## Distance between ribbon cross-sections in metres.
@export var segment_length: float = 3.0
@export_tool_button("Rebuild Water", "Reload") var rebuild_button := rebuild

## Extra width so the ribbon edges tuck under the banks.
const EDGE_TUCK := 0.8


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var layout := WorldLayout.from_json(layout_json)
	if not layout.is_valid():
		return
	var water: Dictionary = layout.data.get("water", {})
	var widths: Dictionary = water.get("widths", {})
	var upper := float(widths.get("river_upper", 6)) * 0.5
	var lower := float(widths.get("river_lower", 11)) * 0.5
	# Same width rule as tools/terrain/generate_terrain.py: narrow above the mill, wide below.
	_ribbon("HavenRiver", water.get("river_profile", []), func(t: float) -> float:
		return lerpf(upper, lower, smoothstep(0.45, 0.62, t)), 0.9)
	var creek := float(widths.get("creek", 5)) * 0.5
	_ribbon("WillowCreek", water.get("creek_profile", []), func(_t: float) -> float: return creek, 0.7)
	var outflow := float(widths.get("outflow", 8)) * 0.5
	_ribbon("LakeOutflow", water.get("outflow_profile", []), func(_t: float) -> float: return outflow, 0.6)
	var lake: Dictionary = water.get("lake", {})
	if not lake.is_empty():
		_lake(WorldLayout.to_vec3(lake["center"]), Vector2(lake["radii"][0], lake["radii"][1]))


func _material(flow_speed: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = water_shader
	material.set_shader_parameter("flow_speed", flow_speed)
	return material


## A strip of water along a profile of [x, z, surface_height] points.
func _ribbon(node_name: String, profile: Array, half_width_at: Callable, flow_speed: float) -> void:
	if profile.size() < 2:
		return
	# Resample the profile every segment_length metres, keeping every original point so short steep
	# drops (waterfalls) stay sharp.
	var points: Array[Vector3] = []
	for i in profile.size() - 1:
		var a := Vector3(profile[i][0], profile[i][2], profile[i][1])
		var b := Vector3(profile[i + 1][0], profile[i + 1][2], profile[i + 1][1])
		var flat := Vector2(b.x - a.x, b.z - a.z).length()
		var steps := maxi(1, int(ceil(flat / segment_length)))
		for s in steps:
			points.append(a.lerp(b, float(s) / steps))
	var last: Array = profile[profile.size() - 1]
	points.append(Vector3(last[0], last[2], last[1]))

	var total := 0.0
	for i in points.size() - 1:
		total += Vector2(points[i + 1].x - points[i].x, points[i + 1].z - points[i].z).length()

	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var along := 0.0
	for i in points.size():
		var prev := points[maxi(i - 1, 0)]
		var next := points[mini(i + 1, points.size() - 1)]
		var dir := Vector2(next.x - prev.x, next.z - prev.z).normalized()
		var side := Vector3(-dir.y, 0.0, dir.x)
		if i > 0:
			along += Vector2(points[i].x - points[i - 1].x, points[i].z - points[i - 1].z).length()
		var half_width: float = half_width_at.call(along / total) + EDGE_TUCK
		vertices.append(points[i] - side * half_width)
		vertices.append(points[i] + side * half_width)
		uvs.append(Vector2(0.0, along))
		uvs.append(Vector2(1.0, along))
		if i > 0:
			var a := (i - 1) * 2
			indices.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var surface := SurfaceTool.new()
	surface.create_from_arrays(arrays)
	surface.generate_normals()
	var mesh := surface.commit()
	mesh.surface_set_material(0, _material(flow_speed))
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


func _lake(centre: Vector3, radii: Vector2) -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.01
	disc.radial_segments = 96
	disc.rings = 1
	disc.cap_bottom = false
	disc.material = _material(0.0)
	var instance := MeshInstance3D.new()
	instance.name = "MirrorLake"
	instance.mesh = disc
	instance.position = Vector3(centre.x, centre.y, centre.z)
	instance.scale = Vector3(radii.x + 1.5, 1.0, radii.y + 1.5)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
