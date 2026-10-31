shader_type spatial;
// Measuring grid for the greybox ground: 1 m lines up close, 10 m lines, and 125 m chunk borders.
// Chunk borders line up with the blueprint grid because they are offset from the world edge at -500.

uniform vec3 base_color : source_color = vec3(0.56, 0.68, 0.46);
uniform vec3 line_color : source_color = vec3(0.30, 0.38, 0.26);
uniform vec3 chunk_color : source_color = vec3(0.93, 0.80, 0.36);
uniform float world_min = -500.0;
uniform float chunk_size = 125.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid_line(vec2 p, float spacing, float half_width) {
	vec2 dist = abs(fract(p / spacing - 0.5) - 0.5) * spacing;
	vec2 aa = fwidth(p) * 1.5;
	vec2 lines = 1.0 - smoothstep(vec2(half_width), vec2(half_width) + aa, dist);
	return max(lines.x, lines.y);
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 fw = fwidth(p);
	// Fade the fine 1 m grid where it would shimmer in the distance.
	float fine_fade = 1.0 - smoothstep(0.05, 0.3, max(fw.x, fw.y));
	float fine = grid_line(p, 1.0, 0.015) * 0.25 * fine_fade;
	float ten = grid_line(p, 10.0, 0.04) * 0.55;
	float chunk = grid_line(p - vec2(world_min), chunk_size, 0.3);
	vec3 col = mix(base_color, line_color, max(fine, ten));
	col = mix(col, chunk_color, chunk);
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
