shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
// Stylized water: turquoise body that darkens with depth, a bright foam rim where it meets the
// ground (like the reference image), foam on waterfalls, and ripples that flow along UV.y.
// UV.y is distance along the river in metres; set flow_speed to 0 for still water (the lake).

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform vec3 shallow_color : source_color = vec3(0.35, 0.85, 0.82);
uniform vec3 deep_color : source_color = vec3(0.07, 0.45, 0.58);
uniform vec3 foam_color : source_color = vec3(0.95, 0.99, 1.0);
uniform float deep_distance = 3.0;
uniform float foam_width = 0.7;
uniform float flow_speed = 0.8;
uniform float ripple_scale = 0.35;

varying vec3 world_normal;
varying vec3 world_pos;

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
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Distance from the water surface to whatever is behind it, along the view ray.
	float raw_depth = texture(depth_texture, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, raw_depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
#endif
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float thickness = max(VERTEX.z - view.z, 0.0);

	vec2 flow = vec2(0.0, -TIME * flow_speed);
	vec2 p = (flow_speed > 0.0 ? UV * vec2(4.0, 1.0) : world_pos.xz) * ripple_scale;
	float n1 = noise(p * 3.0 + flow * ripple_scale * 3.0);
	float n2 = noise(p * 7.0 + flow * ripple_scale * 5.0 + vec2(13.1, 7.7));
	float ripples = n1 * 0.6 + n2 * 0.4;

	float depth_mix = clamp(thickness / deep_distance, 0.0, 1.0);
	vec3 col = mix(shallow_color, deep_color, depth_mix);

	float edge = 1.0 - smoothstep(0.0, foam_width, thickness - (ripples - 0.5) * 0.35);
	float falls = 1.0 - smoothstep(0.35, 0.75, abs(world_normal.y));
	float streaks = smoothstep(0.45, 0.8, noise(vec2(UV.x * 18.0, UV.y * 0.6 - TIME * 3.0)));
	float foam = max(edge, falls * (0.55 + 0.45 * streaks));

	ALBEDO = mix(col, foam_color, foam);
	ALPHA = mix(mix(0.72, 0.95, depth_mix), 1.0, foam);
	ROUGHNESS = mix(0.06, 0.5, foam);
	SPECULAR = 0.6;
	NORMAL_MAP = normalize(vec3(n1 - 0.5, n2 - 0.5, 2.5)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.5;
}
