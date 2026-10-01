shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

// Neblina de sangre de un golpe (CombatFx): manchas suaves de cara a la cámara que crecen y se
// desvanecen (la escala y el alfa los lleva la partícula). Se funden donde tocan el suelo o un
// cuerpo, para que no se vea el corte recto contra la geometría.

uniform vec3 color : source_color = vec3(0.32, 0.015, 0.02);
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
// Distancia (m) a la geometría en la que se funde.
uniform float soft_distance = 0.25;

varying vec2 seed;

void vertex() {
	// Cada mancha su ruido, según dónde nace.
	seed = MODEL_MATRIX[3].xz * 7.0 + MODEL_MATRIX[3].y * 3.0;
	mat4 billboard = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	billboard[0].xyz *= length(MODEL_MATRIX[0].xyz);
	billboard[1].xyz *= length(MODEL_MATRIX[1].xyz);
	billboard[2].xyz *= length(MODEL_MATRIX[2].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float n = noise(UV * 5.0 + seed) * 0.5 + noise(UV * 11.0) * 0.25;
	float density = 1.0 - smoothstep(0.1, 1.0, dot(p, p) + (n - 0.35) * 0.6);
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec4 scene = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float soft = clamp((VERTEX.z - scene.z / scene.w) / soft_distance, 0.0, 1.0);
	ALBEDO = color;
	ROUGHNESS = 0.6;
	ALPHA = density * COLOR.a * soft;
}
