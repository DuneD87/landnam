shader_type spatial;
render_mode cull_disabled, depth_draw_never, blend_mix;

// Hair, second pass: blends the thin fringe of the cards (alpha under the
// first pass's cut) over what is behind, hidden by the solid core in front of
// it. Only faint texels are sorted by draw order, which barely shows.

#include "res://shaders/character/human_hair_common.gdshaderinc"

void vertex() {
	depth_from_body = UV2.x;
	VERTEX = lifted(VERTEX, NORMAL, UV2.x);
}

void fragment() {
	vec4 texel = texture(albedo_texture, UV);
	if (texel.a >= 0.5 || texel.a < 0.02) {
		discard;
	}
	vec3 col = strand_color(texel, UV);
	ALBEDO = col;
	ALPHA = texel.a * 1.4;
	if (use_normal) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
	}
	ROUGHNESS = roughness;
	SPECULAR = 0.18;
	ANISOTROPY = 0.45;
	ANISOTROPY_FLOW = strand_axis == 1 ? vec2(0.0, 1.0) : vec2(1.0, 0.0);
	BACKLIGHT = col * 0.25;
}
