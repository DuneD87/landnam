// Shared by the two passes of the hair (human_hair.gdshader and
// human_hair_fringe.gdshader): uniforms and the strand colour.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic;
uniform bool use_normal = false;
uniform vec3 texture_tone : source_color = vec3(0.3, 0.24, 0.2);
uniform vec3 hair_color : source_color = vec3(0.23, 0.16, 0.11);
uniform float gray : hint_range(0.0, 1.0) = 0.0;
uniform int strand_axis = 1;
uniform float roughness : hint_range(0.0, 1.0) = 0.62;
// How much of the texture's own light and dark shows through the colour
// (the bake already evened it out, tools/character/bake_character_human.gd).
uniform float texture_contrast : hint_range(0.0, 2.0) = 1.0;
// Distance to the body under which the hair darkens, in metres.
uniform float occlusion_depth = 0.02;

const vec3 HAIR_LUMA = vec3(0.2126, 0.7152, 0.0722);
const vec3 GRAY_HAIR = vec3(0.78, 0.77, 0.74);

// Hair fitted flush with the skin (caps at the hairline) dips under it where
// the body's morphs bulge: vertices this close to the body are lifted off it.
uniform float skin_lift = 0.0025;

varying float depth_from_body;

vec3 lifted(vec3 vertex, vec3 normal, float distance_to_body) {
	return vertex + normal * skin_lift * (1.0 - smoothstep(0.0, 0.012, distance_to_body));
}

vec3 hair_to_linear(vec3 c) {
	c = clamp(c, 0.0, 1.0);
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

vec3 hair_to_srgb(vec3 c) {
	c = clamp(c, 0.0, 1.0);
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}

float hair_hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

// hair_color (greyed per strand by `gray`) carrying the texel's brightness
// relative to the texture's mean.
vec3 strand_color(vec4 texel, vec2 uv) {
	float tone_luma = hair_to_srgb(vec3(dot(texture_tone, HAIR_LUMA))).r;
	float relative = hair_to_srgb(vec3(dot(texel.rgb, HAIR_LUMA))).r / max(tone_luma, 0.02);
	relative = pow(clamp(relative, 0.1, 3.0), texture_contrast);
	relative = mix(1.0, relative, smoothstep(0.2, 0.7, texel.a));
	float across = strand_axis == 1 ? uv.x : uv.y;
	float strand_gray = step(1.0 - gray, hair_hash(floor(across * 400.0)) * 0.85 + gray * 0.15);
	vec3 base = mix(hair_color, GRAY_HAIR, max(strand_gray, gray * gray * 0.6));
	vec3 col = hair_to_linear(hair_to_srgb(base) * clamp(relative, 0.3, 1.8));
	float inner = 1.0 - smoothstep(0.0, occlusion_depth, depth_from_body);
	return col * (1.0 - 0.4 * inner);
}
