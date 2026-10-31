class_name GroundView
extends Node2D
## Draws the flat ground of the isometric world as vector shapes: grass, roads, plazas, fields,
## rivers, the lake and bridges.
##
## Everything is drawn in top-down map pixels (the same space as the simulation) and this node's
## transform projects it to the isometric view, so ground shapes always match the collision map.

const INK := Color("3d2a20")
const GRASS_LIGHT := Color("b9e07f")
const GRASS_DARK := Color("a2d06c")
const SAND := Color("ead2a2")
const SAND_DARK := Color("cfb27a")
const COBBLE := Color("ddd3c2")
const SOIL := Color("9c6a45")
const SOIL_ROW := Color("7a4e31")
const WATER_DEEP := Color("2f9fc4")
const WATER := Color("4cc9e2")
const WATER_LIGHT := Color("8fe3ef")
const PLANKS := Color("c99060")
const PLAZA_IDS := ["public_square", "marketplace"]
const FIELD_IDS := ["starter_field", "plot_a", "plot_b", "plot_c", "kitchen_garden", "community_garden"]

const GRASS_SHADER := """
shader_type canvas_item;
uniform vec4 light_color : source_color;
uniform vec4 dark_color : source_color;
void fragment() {
	float n = texture(TEXTURE, UV).r;
	COLOR = mix(dark_color, light_color, smoothstep(0.3, 0.7, n));
}
"""

var _layout: WorldLayout


func build(layout: WorldLayout) -> void:
	_layout = layout
	for child in get_children():
		remove_child(child)
		child.queue_free()
	transform = WorldLayout.iso_transform()
	_grass()
	_areas()
	_roads()
	_water()
	_bridges()


func _px(m: Array) -> Vector2:
	return WorldLayout.to_pixels(float(m[0]), float(m[m.size() - 1]))


func _width(metres: float) -> float:
	return metres * WorldLayout.PX_PER_METRE


# --- Layers ---------------------------------------------------------------------------------------

func _grass() -> void:
	var size := WorldLayout.map_size_px()
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	noise.fractal_octaves = 3
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.noise = noise
	var grass := Polygon2D.new()
	grass.name = "Grass"
	grass.polygon = PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
	grass.texture = texture
	grass.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	grass.uv = PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0) * 0.8, size * 0.8, Vector2(0, size.y) * 0.8])
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = GRASS_SHADER
	material.shader = shader
	material.set_shader_parameter("light_color", GRASS_LIGHT)
	material.set_shader_parameter("dark_color", GRASS_DARK)
	grass.material = material
	add_child(grass)


func _areas() -> void:
	for landmark: Dictionary in _layout.get_landmarks():
		var id: String = landmark.get("id", "")
		var footprint = landmark.get("footprint")
		if not footprint is Array:
			continue
		var c := WorldLayout.to_vec3(landmark["position"])
		var half := Vector2(float(footprint[0]), float(footprint[1])) * 0.5
		var rect := PackedVector2Array([
			WorldLayout.to_pixels(c.x - half.x, c.z - half.y), WorldLayout.to_pixels(c.x + half.x, c.z - half.y),
			WorldLayout.to_pixels(c.x + half.x, c.z + half.y), WorldLayout.to_pixels(c.x - half.x, c.z + half.y)])
		if id in PLAZA_IDS:
			_polygon(rect, COBBLE, 1.2)
			_cobbles(rect)
		elif id in FIELD_IDS:
			_polygon(rect, SOIL, 1.4)
			var rows := int(half.y * 2.0 / 2.0)
			for i in range(1, rows):
				var t := float(i) / rows
				var a := rect[0].lerp(rect[3], t)
				var b := rect[1].lerp(rect[2], t)
				_line(PackedVector2Array([a + (b - a) * 0.03, b - (b - a) * 0.03]), 1.4, SOIL_ROW)


func _roads() -> void:
	for road: Dictionary in _layout.data.get("roads", []):
		var points := PackedVector2Array()
		for p: Array in road.get("points_xz", []):
			points.append(_px(p))
		var width := maxf(_width(float(road.get("width", 3))), 6.0)
		var cobble: bool = road.get("class", "") == "Village street"
		_road(points, width, COBBLE if cobble else SAND)
	for key: String in ["ring_road", "lake_loop"]:
		var loop: Dictionary = _layout.data.get(key, {})
		if loop.is_empty():
			continue
		var points := PackedVector2Array()
		for i in 96:
			var a := TAU * i / 96.0
			points.append(WorldLayout.to_pixels(loop["center_xz"][0] + cos(a) * loop["radii"][0], loop["center_xz"][1] + sin(a) * loop["radii"][1]))
		var road := _road(points, maxf(_width(float(loop.get("width", 3))), 6.0), SAND)
		for line: Line2D in road:
			line.closed = true


func _water() -> void:
	var water: Dictionary = _layout.data.get("water", {})
	var widths: Dictionary = water.get("widths", {})
	for entry: Array in [["river_xz", "river_lower"], ["creek_xz", "creek"], ["outflow_xz", "outflow"]]:
		var points := PackedVector2Array()
		for p: Array in water.get(entry[0], []):
			points.append(_px(p))
		var width := maxf(_width(float(widths.get(entry[1], 6))), 10.0)
		_line(points, width + 7.0, INK)
		_line(points, width + 5.5, SAND)
		_line(points, width + 1.2, INK.lerp(WATER_DEEP, 0.5))
		_line(points, width, WATER_DEEP)
		_line(points, width * 0.62, WATER)
		_line(points, width * 0.22, WATER_LIGHT, 0.7)
	var lake: Dictionary = water.get("lake", {})
	if lake.is_empty():
		return
	var centre := WorldLayout.to_pixels(lake["center"][0], lake["center"][2])
	var radii := Vector2(lake["radii"][0], lake["radii"][1]) * WorldLayout.PX_PER_METRE
	_ellipse(centre, radii + Vector2.ONE * 9.0, SAND, INK, 1.6)
	var ring := _ellipse_points(centre, radii, 96)
	var fan := Polygon2D.new()
	fan.name = "Lake"
	var points := PackedVector2Array([centre]) + ring
	var colors := PackedColorArray([WATER_DEEP.darkened(0.15)])
	var polygons := []
	for i in ring.size():
		colors.append(WATER.lerp(WATER_LIGHT, 0.35))
		polygons.append(PackedInt32Array([0, 1 + i, 1 + (i + 1) % ring.size()]))
	fan.polygon = points
	fan.vertex_colors = colors
	fan.polygons = polygons
	add_child(fan)
	_line(ring, 1.4, INK).closed = true
	_line(_ellipse_points(centre, radii - Vector2.ONE * 3.0, 96), 1.6, Color(1, 1, 1, 0.75)).closed = true
	var island: Dictionary = water.get("island", {})
	if not island.is_empty():
		var ic := WorldLayout.to_pixels(island["center_xz"][0], island["center_xz"][1])
		var r := float(island["radius"]) * WorldLayout.PX_PER_METRE
		_ellipse(ic, Vector2(r + 4, r + 4), SAND, INK, 1.4)
		_ellipse(ic, Vector2(r, r), GRASS_LIGHT.lerp(GRASS_DARK, 0.4), INK, 1.2)


func _bridges() -> void:
	for bridge: Dictionary in _layout.data.get("bridges", []):
		var centre := WorldLayout.to_pixels(bridge["position"][0], bridge["position"][2])
		var angle := deg_to_rad(float(bridge.get("rotation_y_deg", 0)))
		var axis := Vector2(cos(angle), sin(angle))
		var side := axis.orthogonal()
		var half_len := _width(float(bridge.get("span", 10)) * 0.5 + 4.0)
		var half_w := maxf(_width(float(bridge.get("width", 3)) * 0.5), 5.0)
		var deck := PackedVector2Array([centre - axis * half_len - side * half_w, centre + axis * half_len - side * half_w,
			centre + axis * half_len + side * half_w, centre - axis * half_len + side * half_w])
		_polygon(deck, PLANKS, 1.4)
		var planks := int(half_len * 2.0 / 3.0)
		for i in range(1, planks):
			var p := centre - axis * half_len + axis * (half_len * 2.0 * i / planks)
			_line(PackedVector2Array([p - side * half_w, p + side * half_w]), 0.6, PLANKS.darkened(0.35))
		for s in [-1.0, 1.0]:
			_line(PackedVector2Array([centre - axis * half_len + side * half_w * s, centre + axis * half_len + side * half_w * s]), 1.6, PLANKS.darkened(0.45))


# --- Helpers --------------------------------------------------------------------------------------

func _road(points: PackedVector2Array, width: float, color: Color) -> Array:
	return [_line(points, width + 1.6, INK.lerp(color, 0.35)), _line(points, width, color),
		_line(points, width * 0.45, color.lightened(0.18), 0.6)]


func _line(points: PackedVector2Array, width: float, color: Color, alpha: float = 1.0) -> Line2D:
	var line := Line2D.new()
	line.points = points
	line.width = width
	line.default_color = Color(color, alpha)
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	add_child(line)
	return line


func _polygon(points: PackedVector2Array, color: Color, outline: float) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.polygon = points
	poly.color = color
	poly.antialiased = true
	add_child(poly)
	if outline > 0.0:
		_line(points, outline, INK).closed = true
	return poly


func _ellipse(centre: Vector2, radii: Vector2, color: Color, outline_color: Color, outline: float) -> void:
	var points := _ellipse_points(centre, radii, 72)
	var poly := Polygon2D.new()
	poly.polygon = points
	poly.color = color
	poly.antialiased = true
	add_child(poly)
	_line(points, outline, outline_color).closed = true


func _ellipse_points(centre: Vector2, radii: Vector2, count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in count:
		var a := TAU * i / count
		points.append(centre + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return points


func _cobbles(rect: PackedVector2Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(rect[0].x * 13 + rect[0].y)
	var count := int(rect[0].distance_to(rect[1]) * rect[0].distance_to(rect[3]) / 90.0)
	for i in count:
		var p := rect[0].lerp(rect[1], rng.randf()).lerp(rect[3].lerp(rect[2], rng.randf()), rng.randf())
		var stone := Polygon2D.new()
		stone.polygon = _ellipse_points(p, Vector2(rng.randf_range(1.6, 2.6), rng.randf_range(1.2, 2.0)), 8)
		stone.color = COBBLE.darkened(rng.randf_range(0.05, 0.15))
		add_child(stone)
