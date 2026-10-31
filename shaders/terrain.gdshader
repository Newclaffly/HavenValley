shader_type spatial;
// Stylized ground for HeightmapTerrain. Colours come from two painted maps plus the slope:
//   control_map  R dirt road · G tilled soil · B sand / river bed · A cobble
//   zone_map     R forest floor · G meadow flowers · B mountain rock
// Steep ground turns to rock. Small procedural noise breaks up flat colour (no textures needed yet).

uniform sampler2D control_map : filter_linear, repeat_disable;
uniform sampler2D zone_map : filter_linear, repeat_disable;
uniform vec2 world_min = vec2(-512.0);
uniform float world_size = 1024.0;
uniform bool show_chunk_grid = false;

uniform vec3 grass_color : source_color = vec3(0.42, 0.62, 0.27);
uniform vec3 grass_light : source_color = vec3(0.58, 0.74, 0.33);
uniform vec3 forest_color : source_color = vec3(0.27, 0.42, 0.2);
uniform vec3 meadow_color : source_color = vec3(0.66, 0.74, 0.36);
uniform vec3 dirt_color : source_color = vec3(0.6, 0.45, 0.29);
uniform vec3 soil_color : source_color = vec3(0.42, 0.29, 0.18);
uniform vec3 sand_color : source_color = vec3(0.78, 0.71, 0.53);
uniform vec3 cobble_color : source_color = vec3(0.68, 0.64, 0.58);
uniform vec3 rock_color : source_color = vec3(0.52, 0.5, 0.47);
uniform vec3 flower_color : source_color = vec3(0.95, 0.92, 0.82);

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = (world_pos.xz - world_min) / world_size;
	vec4 control = texture(control_map, uv);
	vec3 zones = texture(zone_map, uv).rgb;

	float n_large = noise(world_pos.xz * 0.05);
	float n_small = noise(world_pos.xz * 0.6);

	vec3 col = mix(grass_color, grass_light, smoothstep(0.3, 0.8, n_large) * 0.8 + n_small * 0.2);
	col = mix(col, meadow_color, zones.g * 0.6);
	col = mix(col, forest_color, zones.r);
	// Scattered pale flowers in the meadows.
	float flowers = step(0.93, noise(world_pos.xz * 2.3)) * zones.g;
	col = mix(col, flower_color, flowers * 0.8);

	col = mix(col, soil_color * (0.85 + 0.3 * n_small), control.g);
	col = mix(col, sand_color * (0.9 + 0.2 * n_small), control.b);
	col = mix(col, dirt_color * (0.85 + 0.3 * n_small), control.r);
	// Cobbles: a simple stone pattern on village streets and plazas.
	vec2 cell = fract(world_pos.xz * 1.4);
	float stones = smoothstep(0.0, 0.12, min(min(cell.x, cell.y), min(1.0 - cell.x, 1.0 - cell.y)));
	col = mix(col, cobble_color * (0.75 + 0.25 * stones) * (0.92 + 0.16 * hash(floor(world_pos.xz * 1.4))), control.a);

	// Rock on steep ground and high in the mountains.
	float steep = smoothstep(0.82, 0.62, world_normal.y);
	float rock = max(steep, zones.b * smoothstep(0.9, 0.75, world_normal.y));
	col = mix(col, rock_color * (0.8 + 0.4 * n_small), rock);

	if (show_chunk_grid) {
		vec2 g = abs(fract((world_pos.xz - world_min) / 125.0 - 0.5) - 0.5) * 125.0;
		float line = 1.0 - smoothstep(0.25, 0.25 + fwidth(world_pos.x) * 1.5, min(g.x, g.y));
		col = mix(col, vec3(0.95, 0.82, 0.36), line);
	}

	ALBEDO = col;
	ROUGHNESS = 0.95;
}
