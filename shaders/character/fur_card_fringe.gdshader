shader_type spatial;
render_mode cull_disabled, depth_draw_never, blend_mix;

// Hair cards, second pass: blends the thin ends of the locks (coverage under
// the first pass's cut) over what is behind, hidden by the solid core in
// front of it. Only faint texels are sorted by draw order, which barely shows.

#include "res://shaders/character/fur_common.gdshaderinc"

uniform sampler2D lock_map : filter_linear_mipmap_anisotropic;

void fragment() {
	vec4 texel = texture(lock_map, UV);
	if (texel.a >= 0.5 || texel.a < 0.02) {
		discard;
	}
	vec3 color = fur_color(texel, COLOR.rgb);
	ALBEDO = color;
	ALPHA = texel.a * 1.4;
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
	ROUGHNESS = 0.72;
	SPECULAR = 0.3;
	ANISOTROPY = 0.5;
	ANISOTROPY_FLOW = vec2(0.0, 1.0);
	BACKLIGHT = color * 0.3;
}
