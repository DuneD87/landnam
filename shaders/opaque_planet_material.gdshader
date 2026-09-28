shader_type spatial;
// Material OPACO equivalente a StandardMaterial3D (albedo, metallic, roughness,
// AO, emission) pero iluminado con la luz planetaria custom del proyecto
// (horizonte del planeta por luz, translucencia, rim) y con especular GGX que
// respeta metallic/roughness. El ambiente es el del entorno (cielo del observador).
//
// Pensado para rocas y superficies sólidas sobre el planeta esférico.
// El planeta debe alimentar cada frame light_direction y planet_position
// (planet.gd::_update_planet). Ver planet_lighting.gdshaderinc.

render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/lib/planet_lighting.gdshaderinc"
#include "res://shaders/lib/climate.gdshaderinc"

// --- Albedo ---
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D texture_albedo : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;

// --- Metallic ---
uniform float metallic : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float specular : hint_range(0.0, 1.0, 0.01) = 0.5; // f0 dieléctrico (0.5 -> 0.04)
uniform sampler2D texture_metallic : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 metallic_texture_channel = vec4(1.0, 0.0, 0.0, 0.0);

// --- Roughness ---
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.8;
uniform sampler2D texture_roughness : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 roughness_texture_channel = vec4(1.0, 0.0, 0.0, 0.0);

// --- Normal map ---
// Nota: requiere que la malla tenga UVs + TANGENTES. Si Rock3D no genera
// tangentes, el normal map se verá raro (no cuelga); la solución es generar
// tangentes en la malla, no quitar la feature.
uniform sampler2D texture_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_scale : hint_range(-16.0, 16.0, 0.01) = 1.0;

// --- Oclusión ambiental ---
uniform sampler2D texture_ambient_occlusion : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 ao_texture_channel = vec4(1.0, 0.0, 0.0, 0.0);

// --- Emisión ---
uniform vec4 emission : source_color = vec4(0.0);
uniform sampler2D texture_emission : source_color, hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float emission_energy : hint_range(0.0, 16.0, 0.01) = 1.0;

// --- UV ---
uniform vec3 uv1_scale  = vec3(1.0, 1.0, 1.0);
uniform vec3 uv1_offset = vec3(0.0);

// --- Nieve del clima frío (climate.gdshaderinc) ---
// 0 = nunca (armaduras y props que comparten este shader), 1 = la nieve del sitio sobre las caras
// que miran al cielo y escarcha en el casquete. Lo activan las rocas del planeta.
uniform float climate_snow_amount : hint_range(0.0, 1.0) = 0.0;

varying float v_snow_cover;
varying float v_glacier;

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;

	// Datos en espacio mundo para la iluminación planetaria.
	vertex_position_global = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	planet_normal = normalize(vertex_position_global - planet_position);

	v_snow_cover = 0.0;
	v_glacier = 0.0;
	if (climate_snow_amount > 0.0) {
		float cold = climate_snow_coldness(vertex_position_global - planet_position);
		v_snow_cover = climate_snow_cover(cold) * climate_snow_amount;
		v_glacier = climate_glacier(cold) * climate_snow_amount;
	}
}

void fragment() {
	vec2 base_uv = UV;

	// Albedo
	ALBEDO = (texture(texture_albedo, base_uv) * albedo).rgb;

	// Metallic / specular / roughness (máscaras de canal estilo StandardMaterial3D)
	METALLIC  = metallic * dot(texture(texture_metallic, base_uv), metallic_texture_channel);
	SPECULAR  = specular;
	ROUGHNESS = roughness * dot(texture(texture_roughness, base_uv), roughness_texture_channel);

	// Normal map (el motor lo transforma a espacio mundo con TANGENT/BINORMAL).
	NORMAL_MAP = texture(texture_normal, base_uv).rgb;
	NORMAL_MAP_DEPTH = normal_scale;

	// Oclusión ambiental: la aplica el motor al ambiente del entorno (el cielo).
	AO = dot(texture(texture_ambient_occlusion, base_uv), ao_texture_channel);

	// Emisión
	EMISSION = (emission.rgb + texture(texture_emission, base_uv).rgb) * emission_energy;

	// Nieve y escarcha: con la normal de la malla (antes del normal map), que es la que decide qué
	// cara mira al cielo. La nieve alisa el relieve de la roca que tapa.
	if (v_snow_cover > 0.001 || v_glacier > 0.001) {
		vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 local = vertex_position_global - planet_position;
		float snow = climate_object_snow(v_snow_cover, v_glacier, dot(world_normal, planet_normal), local);
		float rime = v_glacier * (1.0 - snow) * 0.45;
		ALBEDO = mix(ALBEDO, CLIMATE_RIME_ALBEDO, rime);
		ROUGHNESS = mix(ROUGHNESS, 0.35, rime);
		ALBEDO = mix(ALBEDO, CLIMATE_SNOW_ALBEDO, snow);
		ROUGHNESS = mix(ROUGHNESS, 0.85, snow);
		NORMAL_MAP = mix(NORMAL_MAP, vec3(0.5, 0.5, 1.0), snow * 0.8);
		AO = mix(AO, 1.0, snow * 0.5);
	}
}

void light() {
	// SPECULAR no está disponible en light(); pasamos el uniform.
	// Los varyings se LEEN aquí y se pasan como parámetros (no dentro de la función).
	vec3 up_view = normalize((VIEW_MATRIX * vec4(planet_normal, 0.0)).xyz);
	vec3 d, s;
	compute_planet_light(
		NORMAL, VIEW, LIGHT, LIGHT_COLOR, ATTENUATION,
		ALBEDO, METALLIC, ROUGHNESS, specular,
		up_view, LIGHT_IS_DIRECTIONAL, 1.0, d, s);

	DIFFUSE_LIGHT  += d;
	SPECULAR_LIGHT += s;
}
