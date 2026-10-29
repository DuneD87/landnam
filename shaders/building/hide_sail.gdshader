shader_type spatial;
render_mode cull_disabled;

uniform float deployment : hint_range(0.0, 1.0) = 1.0;
uniform float fill : hint_range(0.0, 1.0) = 0.7;
uniform float belly_sign = 1.0;
uniform float wind_speed = 4.0;
// Fase del aleteo, acumulada en hide_sail_visual.gd: con TIME * wind_speed cada racha saltaba.
uniform float flutter_phase = 0.0;
uniform float yard_height = 4.5;
uniform float cloth_height = 3.0;
uniform float cloth_width = 4.0;

void vertex() {
	VERTEX.y = yard_height - (yard_height - VERTEX.y) * mix(0.045, 1.0, deployment);
	float edge = sin(UV.x * 3.14159265);
	float belly = edge * sin(UV.y * 3.14159265);
	float flutter = sin(UV.y * 24.0 + UV.x * 12.0 - flutter_phase);
	VERTEX.z += belly_sign * belly * fill * min(cloth_width, cloth_height) * 0.215 * deployment;
	VERTEX.z += flutter * edge * UV.y * (0.015 + (1.0 - fill) * 0.09) * min(wind_speed * 0.2, 1.0) * deployment;
}

void fragment() {
	vec2 panel = UV * max(vec2(1.0), ceil(vec2(cloth_width, cloth_height)));
	vec2 cell = floor(panel);
	float variation = fract(sin(dot(cell, vec2(17.13, 91.7))) * 43758.5453);
	vec3 hide = mix(vec3(0.47, 0.29, 0.13), vec3(0.75, 0.57, 0.33), variation);
	vec2 seam_distance = min(fract(panel), 1.0 - fract(panel));
	float seam = 1.0 - smoothstep(0.008, 0.028, min(seam_distance.x, seam_distance.y));
	float stitches = step(0.55, fract((seam_distance.x < seam_distance.y ? panel.y : panel.x) * 22.0));
	float grain = sin(UV.x * 820.0 + sin(UV.y * 165.0) * 2.0) * sin(UV.y * 710.0) * 0.025;
	ALBEDO = mix(hide + grain, vec3(0.25, 0.16, 0.085), seam);
	ALBEDO = mix(ALBEDO, vec3(0.85, 0.73, 0.49), seam * stitches * 0.6);
	ROUGHNESS = 0.95;
	vec3 geometric = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	NORMAL = dot(geometric, NORMAL) < 0.0 ? -geometric : geometric;
}
