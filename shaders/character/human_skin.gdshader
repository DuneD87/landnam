shader_type spatial;

// Skin of the MakeHuman bodies (tools/character/bake_character_human.gd).
// Colours are relative to the albedo's own mean tone (texture_tone), so
// skin_color == texture_tone shows the texture as painted. The relief is a
// sculpted normal map whose depth is `definition` (muscle and fat drive it).
// Masks painted from the head's geometry (make_skin_masks.py): R scalp,
// G full beard, B moustache, A goatee; stubble and buzz cuts draw short
// strokes of hair_color there (stubble_texture R). The body masks hold the
// pubic hair fields, R women and G men, from 1 at the core to 0 at the
// fullest reach: pubic_hair sets how far the curls (stubble_texture G) go.
// Lips and eyelids come from MPFB's UV masks.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D masks_texture : hint_default_black, filter_linear_mipmap;
uniform sampler2D stubble_texture : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D body_masks_texture : hint_default_black, filter_linear_mipmap;
uniform sampler2D lips_mask : hint_default_black, filter_linear_mipmap;
uniform sampler2D eyelids_mask : hint_default_black, filter_linear_mipmap;
uniform vec3 texture_tone : source_color = vec3(0.88, 0.66, 0.54);
uniform vec3 skin_color : source_color = vec3(0.88, 0.66, 0.54);
uniform float definition : hint_range(0.0, 3.0) = 1.0;
uniform vec3 lip_color : source_color = vec3(0.72, 0.38, 0.36);
uniform float lip_tint : hint_range(0.0, 1.0) = 0.0;
uniform vec3 eyeshadow_color : source_color = vec3(0.25, 0.2, 0.2);
uniform float eyeshadow : hint_range(0.0, 1.0) = 0.0;
uniform vec3 hair_color : source_color = vec3(0.16, 0.11, 0.08);
uniform float stubble : hint_range(0.0, 1.0) = 0.0;
uniform float scalp_hair : hint_range(0.0, 1.0) = 0.0;
// Under a haircut the roots reach a little past the scalp mask (0-1), so the
// skin at the hair's edge is not bare.
uniform float scalp_spread : hint_range(0.0, 1.0) = 0.0;
// Stubble texture repeats per UV unit (the face spans about 0.25).
uniform float stubble_scale = 2.0;
uniform float pubic_hair : hint_range(0.0, 1.0) = 0.0;
// 0 the women's pubic field, 1 the men's.
uniform float male_pattern : hint_range(0.0, 1.0) = 0.0;
uniform float curl_scale = 2.5;
uniform float roughness : hint_range(0.0, 1.0) = 0.6;
uniform float subsurface : hint_range(0.0, 1.0) = 0.3;

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
	vec3 base = texture(albedo_texture, UV).rgb;
	vec3 tone = max(texture_tone, vec3(0.01));
	vec3 col = base * skin_color / tone;
	// Brightness of the texel relative to the skin around it, in sRGB.
	float relative = to_srgb(vec3(dot(base, LUMA))).r / max(to_srgb(vec3(dot(tone, LUMA))).r, 0.01);

	float lips = texture(lips_mask, UV).r * lip_tint;
	col = mix(col, to_linear(to_srgb(lip_color) * clamp(relative, 0.0, 1.4)), lips);
	float lids = texture(eyelids_mask, UV).r * eyeshadow;
	col = mix(col, to_linear(to_srgb(eyeshadow_color) * clamp(relative, 0.0, 1.4)), lids);

	// Stubble and buzz cut: a shadow of the hair colour and its strokes.
	vec4 masks = texture(masks_texture, UV);
	float strokes = texture(stubble_texture, UV * stubble_scale).r;
	// The scalp's hair is denser: a second, finer layer of strokes.
	float dense = max(strokes, texture(stubble_texture, UV * stubble_scale * 1.7 + vec2(0.37, 0.61)).r);
	float beard = masks.g * stubble;
	float spread = clamp(max(textureLod(masks_texture, UV, 3.5).r * 1.8, textureLod(masks_texture, UV, 5.0).r * 2.2 - 0.25), 0.0, 1.0) * scalp_spread;
	float scalp = max(masks.r, spread) * scalp_hair;
	float shade = max(beard * 0.55, scalp * 0.9);
	vec3 hair = hair_color * (0.55 + 0.45 * strokes);
	col = mix(col, mix(col * 0.8, hair, mix(0.35, 0.6, scalp)), shade);
	col = mix(col, hair, clamp(max(beard * 0.9 * strokes, scalp * dense), 0.0, 1.0));

	// Pubic hair: a shadow of the hair colour and dense curls, thinning out
	// towards the edge.
	vec2 body_masks = texture(body_masks_texture, UV).rg;
	float field = mix(body_masks.r, body_masks.g, male_pattern);
	float pubic = smoothstep(1.0 - pubic_hair, 1.0 - pubic_hair + 0.2, field) * step(0.005, pubic_hair);
	float curls = max(texture(stubble_texture, UV * curl_scale).g,
			texture(stubble_texture, UV * curl_scale * 1.9 + vec2(0.53, 0.19)).g * 0.85);
	// Clumps: denser and sparser patches at a coarser scale.
	float clumps = texture(stubble_texture, UV * curl_scale * 0.45 + vec2(0.21, 0.77)).g;
	vec3 pubic_color = hair_color * 0.85;
	float cover = pubic * (0.7 + 0.3 * smoothstep(0.0, 0.5, clumps));
	col = mix(col, mix(col * 0.55, pubic_color * 0.7, 0.6), cover * 0.9);
	col = mix(col, pubic_color * (0.8 + 0.6 * curls), cover * smoothstep(0.05, 0.6, curls) * 0.85);
	shade = max(shade, pubic);

	ALBEDO = col;
	NORMAL_MAP = texture(normal_texture, UV).rgb;
	NORMAL_MAP_DEPTH = definition;
	ROUGHNESS = mix(mix(roughness, 0.42, lips * 0.6 + texture(lips_mask, UV).r * 0.3), 0.85, shade);
	SPECULAR = 0.4;
	SSS_STRENGTH = subsurface;
}
