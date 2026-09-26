// =============================================================================
//  tree_impostor.gdshader
//  Aspa billboard usada como LOD3 de los árboles (ver planet.gd::_bake_tree_impostor).
//  Es "unshaded" (barato de lejos): sin light(), se ilumina a mano con las MISMAS
//  radiancias que las luces reales de la escena (uniforms globales de SkyLighting):
//  sol y luna, cada uno con su horizonte, más el ambiente del cielo. Así el bosque
//  lejano se dora al atardecer, se azula con la luna y casa con el cercano, en vez
//  de brillar a albedo pleno de día y quedarse a un 20% fijo de noche.
//
//  planet.gd empuja cada frame planet_position (igual que a los materiales de
//  follaje, vía item_transparent_materials). NO renombrar.
// =============================================================================
shader_type spatial;
render_mode unshaded, cull_disabled;

// Solo el fundido por distancia (tree_band_fades); los uniforms de viento no se usan.
#include "res://shaders/lib/tree_wind.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0, 0.01) = 0.5;

// Alimentado por el planeta (mismo nombre que en planet_lighting.gdshaderinc).
uniform vec3 planet_position;
// Fracción media de la luz directa que recibe una copa vista de lejos: su cara al sol,
// su cara en sombra y lo que se tapa a sí misma.
uniform float direct_fraction : hint_range(0.0, 1.0, 0.01) = 0.55;

global uniform vec3 sky_sun_radiance;
global uniform vec3 sky_sun_direction;
global uniform vec3 sky_moon_radiance;
global uniform vec3 sky_moon_direction;
global uniform vec3 sky_ambient_radiance;

varying vec3 light_rgb;
varying vec2 v_band;

void vertex() {
	v_band = tree_band_fades(MODEL_MATRIX[3].xyz, MAIN_CAM_INV_VIEW_MATRIX);
	if (min(v_band.x, v_band.y) <= 0.0) {
		VERTEX = vec3(0.0);
	}
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 up = normalize(world_pos - planet_position);
	// Mismo horizonte por luz que la vegetación cercana (planet_lighting.gdshaderinc).
	float sun_vis = smoothstep(-0.035, 0.035, dot(up, sky_sun_direction));
	float moon_vis = smoothstep(-0.035, 0.035, dot(up, sky_moon_direction));
	light_rgb = (sky_sun_radiance * sun_vis + sky_moon_radiance * moon_vis) * direct_fraction
		+ sky_ambient_radiance;
}

void fragment() {
	if (tree_band_discard(v_band, FRAGCOORD.xy)) {
		discard;
	}
	vec4 tex = texture(albedo_texture, UV);
	if (tex.a < alpha_scissor_threshold) {
		discard;
	}
	ALBEDO = tex.rgb * light_rgb;
}
