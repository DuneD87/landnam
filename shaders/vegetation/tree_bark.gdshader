// =============================================================================
//  tree_bark.gdshader
//  Corteza de los árboles del generador Branching (Tree3D): albedo, normal y rugosidad
//  con UV en metros de corteza, oclusión horneada en COLOR.r (base del tronco y ramas
//  dentro de la copa), musgo en las caras que miran al cielo y en la base, y una
//  variación de tono por árbol. Mismo viento que el follaje (tree_wind.gdshaderinc).
// =============================================================================
shader_type spatial;
render_mode depth_draw_opaque, cull_back;

#include "res://shaders/lib/planet_lighting.gdshaderinc"
#include "res://shaders/lib/tree_wind.gdshaderinc"
#include "res://shaders/lib/climate.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D texture_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D texture_roughness : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float normal_scale : hint_range(0.0, 4.0, 0.01) = 1.0;
uniform float roughness_min : hint_range(0.0, 1.0, 0.01) = 0.55;
uniform float specular_strength : hint_range(0.0, 1.0, 0.01) = 0.25;
// Oclusión horneada: 0 la ignora, 1 la aplica entera.
uniform float ao_strength : hint_range(0.0, 1.0, 0.01) = 1.0;
// Parte de la oclusión que también atenúa la luz directa (sombra propia de la copa).
uniform float direct_occlusion : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform vec4 moss_color : source_color = vec4(0.26, 0.31, 0.12, 1.0);
uniform float moss_amount : hint_range(0.0, 1.0, 0.01) = 0.35;
// Variación de brillo y temperatura entre árboles.
uniform float tint_variation : hint_range(0.0, 0.5, 0.01) = 0.12;

varying float v_ao;
varying vec2 v_band;
varying float v_moss;
varying vec3 v_tint;
// Nieve del clima frío: cobertura del sitio del árbol, casquete y cara hacia el cielo (con la
// ventisca de la base sumada).
varying float v_snow_cover;
varying float v_glacier;
varying float v_snow_facing;

void vertex() {
	vec3 relative_base = MODEL_MATRIX[3].xyz - planet_position;
	vec3 up = tree_up(relative_base);
	float seed = tree_seed(relative_base, 17u);
	v_band = tree_band_fades(MODEL_MATRIX[3].xyz, MAIN_CAM_INV_VIEW_MATRIX);
	VERTEX += tree_wind_offset(VERTEX, NORMAL, COLOR, UV2, MODEL_MATRIX, up, seed, TIME);
	// Fuera de su banda el árbol se colapsa: triángulos degenerados, sin rasterizar nada.
	float camera_distance = distance(MODEL_MATRIX[3].xyz, MAIN_CAM_INV_VIEW_MATRIX[3].xyz);
	if (min(v_band.x, v_band.y) <= 0.0 || (IN_SHADOW_PASS && tree_shadow_skip(COLOR, UV2, camera_distance))) {
		VERTEX = vec3(0.0);
	}

	vertex_position_global = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	planet_normal = normalize(vertex_position_global - planet_position);

	vec3 world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float facing_sky = smoothstep(0.15, 0.85, dot(world_normal, up));
	float base = 1.0 - smoothstep(0.0, 1.4, VERTEX.y * length(MODEL_MATRIX[1].xyz));
	v_moss = clamp(facing_sky * 0.8 + base * 0.7, 0.0, 1.0) * moss_amount;
	v_ao = mix(1.0, COLOR.r, ao_strength);
	// Un frío por árbol (en su base): la corteza, la copa y el impostor nievan igual.
	v_snow_cover = 0.0;
	v_glacier = 0.0;
	v_snow_facing = 0.0;
	if (!IN_SHADOW_PASS) {
		float cold = climate_snow_coldness(relative_base);
		v_snow_cover = climate_snow_cover(cold);
		v_glacier = climate_glacier(cold);
		v_snow_facing = dot(world_normal, up) + base * 0.9;
	}
	float seed2 = tree_seed(relative_base, 91u);
	v_tint = vec3(1.0 + (seed - 0.5) * 2.0 * tint_variation)
		* mix(vec3(0.96, 1.0, 1.04), vec3(1.04, 1.0, 0.95), seed2);
}

void fragment() {
	if (tree_band_discard(v_band, FRAGCOORD.xy)) {
		discard;
	}
	vec3 bark = texture(texture_albedo, UV).rgb * albedo.rgb * v_tint;
	// El musgo se queda en los surcos claros de la textura, no como una capa lisa.
	float luma = dot(bark, vec3(0.2126, 0.7152, 0.0722));
	float moss = v_moss * smoothstep(0.05, 0.35, luma + v_moss * 0.3);
	ALBEDO = mix(bark, moss_color.rgb * (0.7 + luma), moss);
	if (v_snow_cover > 0.001) {
		// Nieve sobre las ramas y al pie del tronco; se queda en los surcos claros primero.
		float snow = climate_object_snow(v_snow_cover, v_glacier, v_snow_facing + (luma - 0.3) * 0.4,
			vertex_position_global - planet_position);
		ALBEDO = mix(ALBEDO, CLIMATE_SNOW_ALBEDO, snow);
	}
	NORMAL_MAP = texture(texture_normal, UV).rgb;
	NORMAL_MAP_DEPTH = normal_scale;
	ROUGHNESS = max(texture(texture_roughness, UV).r, roughness_min);
	SPECULAR = specular_strength;
	AO = v_ao;
	AO_LIGHT_AFFECT = 0.0;
}

void light() {
	float ndl = max(dot(NORMAL, LIGHT), 0.0);
	float day = LIGHT_IS_DIRECTIONAL
		? planet_light_visibility(normalize((VIEW_MATRIX * vec4(planet_normal, 0.0)).xyz), LIGHT)
		: 1.0;
	float occlusion = mix(1.0, v_ao, direct_occlusion);
	vec3 energy = LIGHT_COLOR * ATTENUATION * day * occlusion;
	DIFFUSE_LIGHT += ndl / PI * energy;
	vec3 half_sum = LIGHT + VIEW;
	vec3 half_vector = half_sum / max(length(half_sum), 0.0001);
	float gloss = pow(max(dot(NORMAL, half_vector), 0.0), mix(48.0, 8.0, ROUGHNESS));
	SPECULAR_LIGHT += gloss * specular_strength * 0.15 * (1.0 - ROUGHNESS) * ndl * energy;
}
