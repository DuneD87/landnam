shader_type spatial;

// The hide of a pelt worn with the hair out, under its hair cards: the coat
// seen between them, from a tile of combed hair that repeats every
// 1 / map_scale metres (the garments' UVs are in metres, +V down the pelt).

#include "res://shaders/character/fur_common.gdshaderinc"

uniform sampler2D pelt_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D pelt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float map_scale = 12.5;

void fragment() {
	vec2 uv = UV * map_scale;
	vec3 color = fur_color(texture(pelt_map, uv), COLOR.rgb);
	ALBEDO = color;
	NORMAL_MAP = texture(pelt_normal, uv).rgb;
	NORMAL_MAP_DEPTH = 0.6;
	ROUGHNESS = 0.8;
	SPECULAR = 0.25;
	BACKLIGHT = color * 0.15;
}
