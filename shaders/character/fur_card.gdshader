shader_type spatial;
render_mode cull_disabled;

// Hair cards of the fur garments, first pass: the solid core of each lock,
// cut at half coverage (alpha to coverage under MSAA). fur_card_fringe, the
// next pass, blends what it cuts away. A card is lit with the normal of the
// coat it grows from (its vertex normal) on both faces, so the fur shades as
// one surface and not as flat strips; the highlight runs along the strands.

#include "res://shaders/character/fur_common.gdshaderinc"

uniform sampler2D lock_map : filter_linear_mipmap_anisotropic;

void fragment() {
	vec4 texel = texture(lock_map, UV);
	vec3 color = fur_color(texel, COLOR.rgb);
	ALBEDO = color;
	ALPHA = texel.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.25;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(lock_map, 0));
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
	ROUGHNESS = 0.72;
	SPECULAR = 0.3;
	ANISOTROPY = 0.5;
	ANISOTROPY_FLOW = vec2(0.0, 1.0);
	BACKLIGHT = color * 0.3;
}
