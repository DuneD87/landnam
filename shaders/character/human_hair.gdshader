shader_type spatial;
render_mode cull_disabled;

// Hair and beards, first pass: the solid core of the MakeHuman hair cards,
// opaque, cut at half alpha with alpha to coverage for soft edges under MSAA.
// The strands' colour is hair_color relative to the texture's own mean tone
// (human_hair_common.gdshaderinc), the highlight runs along them (strand_axis
// says whether they follow U or V) and hair near the scalp (UV2.x, distance to
// the body) is shaded as inner layers are. human_hair_fringe.gdshader, the
// next pass, blends the thin fringe this pass cuts away.

#include "res://shaders/character/human_hair_common.gdshaderinc"

void vertex() {
	depth_from_body = UV2.x;
	VERTEX = lifted(VERTEX, NORMAL, UV2.x);
}

void fragment() {
	vec4 texel = texture(albedo_texture, UV);
	vec3 col = strand_color(texel, UV);
	ALBEDO = col;
	ALPHA = texel.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.25;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(albedo_texture, 0));
	if (use_normal) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
	}
	ROUGHNESS = roughness;
	SPECULAR = 0.18;
	ANISOTROPY = 0.45;
	ANISOTROPY_FLOW = strand_axis == 1 ? vec2(0.0, 1.0) : vec2(1.0, 0.0);
	BACKLIGHT = col * 0.25;
	float inner = 1.0 - smoothstep(0.0, occlusion_depth, depth_from_body);
	AO = 1.0 - 0.5 * inner;
	AO_LIGHT_AFFECT = 0.35;
}
