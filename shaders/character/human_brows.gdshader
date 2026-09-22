shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

// Eyebrows and eyelashes. Their MakeHuman textures are soft strokes whose
// alpha rarely reaches one half, so they are alpha blended (they lie on the
// skin, a single layer, so sorting is not an issue) and `density` thickens
// them. Colour as in human_hair.gdshader: hair_color relative to the
// texture's own mean tone, or flat for near-black textures.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 texture_tone : source_color = vec3(0.07, 0.04, 0.035);
uniform vec3 hair_color : source_color = vec3(0.23, 0.16, 0.11);
uniform float density : hint_range(0.5, 3.0) = 2.2;

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
	float tone_luma = to_srgb(vec3(dot(texture_tone, LUMA))).r;
	float relative = to_srgb(vec3(dot(texel.rgb, LUMA))).r / max(tone_luma, 0.02);
	relative = mix(1.0, relative, smoothstep(0.05, 0.1, tone_luma));
	ALBEDO = to_linear(to_srgb(hair_color) * clamp(relative, 0.6, 1.4));
	ALPHA = clamp(texel.a * density, 0.0, 1.0);
	ROUGHNESS = 0.7;
	SPECULAR = 0.2;
}
