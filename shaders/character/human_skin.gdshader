shader_type spatial;

// Skin of the MakeHuman bodies (tools/character/bake_character_human.gd).
// Colours are relative to the albedo's own mean tone (texture_tone), so
// skin_color == texture_tone shows the texture as painted. Lips and eyelids
// come from MPFB's UV masks; the underwear is cut by the rest height of each
// vertex (UV2.x, identical for both sexes because it belongs to the vertex),
// never on the arms (UV2.y is the arm weight), so hands at hip height stay bare.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D lips_mask : hint_default_black, filter_linear_mipmap;
uniform sampler2D eyelids_mask : hint_default_black, filter_linear_mipmap;
uniform vec3 texture_tone : source_color = vec3(0.88, 0.66, 0.54);
uniform vec3 skin_color : source_color = vec3(0.88, 0.66, 0.54);
uniform vec3 lip_color : source_color = vec3(0.72, 0.38, 0.36);
uniform float lip_tint : hint_range(0.0, 1.0) = 0.0;
uniform vec3 eyeshadow_color : source_color = vec3(0.25, 0.2, 0.2);
uniform float eyeshadow : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.55;
uniform float subsurface : hint_range(0.0, 1.0) = 0.35;

uniform vec3 underwear_color : source_color = vec3(0.05, 0.047, 0.045);
// Rest heights (bottom, top) in the player skin space.
uniform vec2 briefs_band = vec2(-0.1, 0.12);
uniform float briefs : hint_range(0.0, 1.0) = 1.0;
uniform vec2 top_band = vec2(0.3, 0.46);
uniform float top_cover : hint_range(0.0, 1.0) = 0.0;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

varying vec2 rest;

vec3 to_linear(vec3 c) {
	c = clamp(c, 0.0, 1.0);
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

vec3 to_srgb(vec3 c) {
	c = clamp(c, 0.0, 1.0);
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}

// Anti-aliased 0..1 between two heights.
float band(float height, vec2 range) {
	float edge = max(fwidth(height), 0.0005);
	return smoothstep(range.x - edge, range.x + edge, height) * (1.0 - smoothstep(range.y - edge, range.y + edge, height));
}

void vertex() {
	rest = UV2;
}

void fragment() {
	vec3 base = texture(albedo_texture, UV).rgb;
	vec3 tone = max(texture_tone, vec3(0.01));
	vec3 col = base * skin_color / tone;
	// Brightness of the texel relative to the skin around it, in sRGB.
	float relative = to_srgb(vec3(dot(base, LUMA))).r / max(to_srgb(vec3(dot(tone, LUMA))).r, 0.01);

	float lips = texture(lips_mask, UV).r * lip_tint;
	col = mix(col, to_linear(to_srgb(lip_color) * clamp(relative, 0.0, 1.4)), lips);
	float lids = texture(eyelids_mask, UV).r * eyeshadow;
	col = mix(col, to_linear(to_srgb(eyeshadow_color) * clamp(relative, 0.0, 1.4)), lids);

	float bare_arm = 1.0 - smoothstep(0.3, 0.6, rest.y);
	float cover = max(band(rest.x, briefs_band) * briefs, band(rest.x, top_band) * top_cover) * bare_arm;
	col = mix(col, underwear_color * (0.8 + 0.4 * relative), cover);

	ALBEDO = col;
	ROUGHNESS = mix(roughness, 0.85, max(cover, lips * 0.4));
	SSS_STRENGTH = subsurface * (1.0 - cover);
}
