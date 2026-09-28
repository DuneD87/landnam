shader_type canvas_item;
// Sonda de tests/climate/test_climate_field.gd: pinta el ruido del frío (r) y el hielo marino (g).
#include "res://shaders/lib/climate.gdshaderinc"

uniform sampler2D points : filter_nearest;
uniform int count = 1;

void fragment() {
	int i = int(FRAGCOORD.x);
	vec3 p = texelFetch(points, ivec2(i, 0), 0).xyz;
	float height = length(p) - climate_shape.x;
	float noise = climate_coldness(p) - climate_latitude(p) - climate_shape.y * max(height - climate_shape.z, 0.0);
	float shore = float(i % 5) * 80.0 - 1.0;
	COLOR = vec4(noise / 20.0 + 0.5, climate_sea_ice_at(p, shore), 0.0, 1.0);
}
