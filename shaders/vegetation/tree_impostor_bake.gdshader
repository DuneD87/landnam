// =============================================================================
//  tree_impostor_bake.gdshader
//  Horneado de los atlas de impostor octaédrico (tools/vegetation/bake_tree_impostors.gd).
//  Sin luz: mode 0 escribe el color (con la oclusión horneada suavizada) y la cobertura;
//  mode 1 escribe la normal de la copa en octaédrico (RG) y la oclusión (B).
//  El viewport convierte de lineal a sRGB al guardar: en mode 1 se deshace esa conversión
//  para que los bytes guardados sean exactamente los valores codificados.
// =============================================================================
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

#include "res://shaders/lib/octahedral.gdshaderinc"

uniform int mode = 0;
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform float saturation = 1.0;
uniform float alpha_scissor_threshold = 0.4;
uniform bool is_foliage = true;
// Parte de la oclusión que se hornea en el color (la otra va al canal B de la normal).
uniform float ao_in_albedo = 0.35;

varying vec3 v_normal;
varying float v_ao;

void vertex() {
	v_normal = NORMAL;
	v_ao = COLOR.r;
}

vec3 linear_from_srgb(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	vec4 tex = texture(texture_albedo, UV);
	float alpha = is_foliage ? tex.a : 1.0;
	if (alpha < alpha_scissor_threshold) {
		discard;
	}
	if (mode == 0) {
		vec3 color = tex.rgb * albedo_tint.rgb;
		float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
		color = mix(vec3(luma), color, saturation);
		ALBEDO = color * mix(1.0, v_ao, ao_in_albedo);
	} else {
		ALBEDO = linear_from_srgb(vec3(oct_normal_encode(normalize(v_normal)), v_ao));
	}
}
