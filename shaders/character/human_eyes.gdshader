shader_type spatial;

// MakeHuman eyeballs. Both eyes share one texture with the two irises at
// fixed UV centres; a radial mask around them retints the iris with
// eye_color, keeping its fibres (the texel's brightness) and the pupil. The
// mesh also has a cornea shell mapped to a fully transparent patch: it is cut
// away, and the eyeball itself carries the wet highlight.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 eye_color : source_color = vec3(0.25, 0.4, 0.6);

const vec2 IRIS_A = vec2(0.293, 0.703);
const vec2 IRIS_B = vec2(0.707, 0.293);
const float IRIS_RADIUS = 0.113;
const float PUPIL_RADIUS = 0.034;
// Brightness of the painted iris fibres (sRGB).
const float IRIS_LUMA = 0.55;
const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

vec3 to_linear(vec3 c) {
	c = clamp(c, 0.0, 1.0);
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

vec3 to_srgb(vec3 c) {
	c = clamp(c, 0.0, 1.0);
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}

void fragment() {
	vec4 texel = texture(albedo_texture, UV);
	vec3 base = texel.rgb;
	ALPHA = texel.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	float d = min(distance(UV, IRIS_A), distance(UV, IRIS_B));
	float iris = (1.0 - smoothstep(IRIS_RADIUS - 0.008, IRIS_RADIUS + 0.004, d)) * smoothstep(PUPIL_RADIUS - 0.004, PUPIL_RADIUS + 0.004, d);
	float luma = to_srgb(vec3(dot(base, LUMA))).r;
	vec3 tinted = to_linear(to_srgb(eye_color) * clamp(luma / IRIS_LUMA, 0.2, 1.6));
	ALBEDO = mix(base, tinted, iris);
	// Wet look: the cornea is part of the same surface.
	ROUGHNESS = 0.06;
	SPECULAR = 0.65;
}
