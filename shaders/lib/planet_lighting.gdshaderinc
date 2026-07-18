// =============================================================================
//  planet_lighting.gdshaderinc
//  Fuente de verdad ÚNICA de la iluminación planetaria custom.
//
//  Reúne lo que antes estaba duplicado en grass_wind y transparent_material_shader:
//    1. Difuso Lambert
//    2. Especular GGX/Cook-Torrance (respeta metallic/roughness, estilo StandardMaterial3D)
//    3. Translucencia / SSS (luz a contraluz que atraviesa el material)
//    4. Fresnel / Rim
//    5. Ambient hemisférico (cielo/suelo)
//    6. Sombra planetaria (terminador día/noche)
//
//  IMPORTANTE (bug de compilación): la función NO lee los varyings como globales.
//  Acceder a un `varying` dentro de una función auxiliar llamada desde light()
//  cuelga el compilador de Godot. Por eso world_pos/planet_n se pasan como
//  parámetros y los varyings solo se leen DIRECTAMENTE dentro de light().
//
//  Uso desde un shader spatial:
//    #include "res://shaders/lib/planet_lighting.gdshaderinc"
//
//    En vertex() rellena los varyings (terminador y ambient se precalculan ahí
//    porque son señales de frecuencia planetaria; por píxel eran coste inútil):
//      vertex_position_global = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; // tras viento, si lo hay
//      planet_normal          = normalize(vertex_position_global - planet_position);
//      float day_f; vec3 amb;
//      compute_planet_vertex_light(vertex_position_global, planet_normal, day_f, amb);
//      planet_day_factor = day_f;
//      planet_ambient    = amb;
//
//    En light():
//      vec3 d, s;
//      compute_planet_light(NORMAL, VIEW, LIGHT, LIGHT_COLOR, ATTENUATION,
//          ALBEDO, METALLIC, ROUGHNESS, specular_uniform, 1.0,
//          planet_day_factor, planet_ambient, LIGHT_IS_DIRECTIONAL, d, s);
//      DIFFUSE_LIGHT  += d;   // el motor multiplica DIFFUSE_LIGHT por ALBEDO
//      SPECULAR_LIGHT += s;   // opcional (grass/transparent lo omiten)
//
//  El planeta (planet.gd::_update_planet) escribe cada frame light_direction y
//  planet_position sobre cada material. NO renombrar esos uniforms.
// =============================================================================
#ifndef PLANET_LIGHTING_INC
#define PLANET_LIGHTING_INC

// --- Alimentados por el planeta ---
uniform vec3  light_direction = vec3(1.0, 0.0, 0.0);
uniform vec3  planet_position;
uniform float transition_width : hint_range(0.0, 1.0, 0.01) = 0.2; // ancho del terminador

// --- Ambient hemisférico ---
uniform float ambient_intensity : hint_range(0.0, 1.0, 0.01) = 0.15;
uniform vec4  ambient_color_top    : source_color = vec4(0.6, 0.7, 1.0, 1.0); // cielo
uniform vec4  ambient_color_bottom : source_color = vec4(0.2, 0.15, 0.1, 1.0); // suelo

// --- Translucencia / SSS ---
uniform float translucency_strength : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform vec4  translucency_color : source_color = vec4(0.8, 1.0, 0.4, 1.0); // tinte al atravesar
uniform float translucency_power : hint_range(1.0, 8.0, 0.1) = 2.0;

// --- Rim / Fresnel ---
uniform float rim_strength : hint_range(0.0, 1.0, 0.01) = 0.3;

// Posición mundo (tras viento si lo hubiera) y dirección radial del planeta.
// Se rellenan en el vertex() de cada shader que incluya este archivo y se LEEN
// solo dentro de light() (nunca dentro de la función auxiliar).
varying vec3 vertex_position_global;
varying vec3 planet_normal;

// Señales del sol precalculadas por vértice: terminador día/noche (0 noche,
// 1 día) y ambient hemisférico (con intensity incluida, sin attenuation).
varying float planet_day_factor;
varying vec3  planet_ambient;

// Calcula las señales de baja frecuencia del sol para un vértice. Llamar desde
// vertex() con locales y copiar el resultado a planet_day_factor/planet_ambient.
void compute_planet_vertex_light(vec3 world_pos, vec3 planet_n,
		out float out_day_factor, out vec3 out_ambient) {
	vec3 sun_dir = normalize(-light_direction);
	vec3 to_planet = normalize(planet_position - world_pos);
	out_day_factor = smoothstep(-transition_width, transition_width, dot(to_planet, sun_dir));
	float hemisphere_factor = dot(planet_n, sun_dir) * 0.5 + 0.5;
	out_ambient = mix(ambient_color_bottom.rgb, ambient_color_top.rgb, hemisphere_factor) * ambient_intensity;
}

// out_diffuse  -> DIFFUSE_LIGHT  (el motor lo multiplica por ALBEDO)
// out_specular -> SPECULAR_LIGHT (NO se multiplica por ALBEDO)
//
// is_directional distingue el sol (luz direccional) de las luces locales
// (antorchas, hogueras...). El terminador día/noche y el ambient hemisférico
// solo tienen sentido para el sol; aplicarlos a una luz local la apagaría de
// noche (planet_shadow ~ 0) y sumaría el ambient una vez por luz. Pasa
// LIGHT_IS_DIRECTIONAL desde el light() de cada shader.
void compute_planet_light(
		vec3 N, vec3 V, vec3 L, vec3 light_color, float attenuation,
		vec3 albedo, float metallic, float roughness, float specular_amount, float ao,
		float day_factor, vec3 ambient_rgb, bool is_directional,
		out vec3 out_diffuse, out vec3 out_specular) {

	vec3 light_energy = attenuation * light_color;

	float NdotL = clamp(dot(N, L), 0.0, 1.0);
	float NdotV = clamp(dot(N, V), 0.0, 1.0);

	// === 1. Difuso Lambert (sin albedo: lo aplica el motor; los metales no tienen difuso) ===
	vec3 diffuse = vec3(NdotL / PI) * (1.0 - metallic);

	// === 2. Especular: TEMPORALMENTE DESACTIVADO ===
	// El GGX completo aquí disparaba el tiempo de compilación (cuelgue). Lo
	// reintroduciremos con una versión más barata una vez confirmado que carga.
	vec3 specular = vec3(0.0);

	// === 3. Translucencia / SSS (luz que atraviesa el material a contraluz) ===
	vec3  back_light  = normalize(-L + N * 0.3);
	float VdotBL      = clamp(dot(V, back_light), 0.0, 1.0);
	float back_factor = pow(clamp(-dot(N, L), 0.0, 1.0), 6.0);
	float sss = pow(VdotBL, translucency_power) * translucency_strength * back_factor;
	vec3  translucency = sss * translucency_color.rgb;

	// === 4. Fresnel / Rim ===
	float fresnel = pow(1.0 - NdotV, 3.0);
	vec3  rim = vec3(fresnel * rim_strength / PI);

	vec3 lit = (diffuse + translucency + rim) * light_energy;

	// Luces locales (antorchas, etc.): sin terminador planetario ni ambient
	// (el ambient lo aporta solo el sol). Así iluminan también de noche.
	if (!is_directional) {
		out_diffuse  = lit;
		out_specular = specular * light_energy;
		return;
	}

	// === 5+6. Ambient hemisférico y terminador día/noche ===
	// Precalculados por vértice en compute_planet_vertex_light; aquí solo se
	// aplica la attenuation (por luz) y se compone.
	vec3 ambient = ambient_rgb * attenuation;

	// === Composición ===
	out_diffuse  = lit * day_factor
				 + ambient * mix(0.3, 1.0, day_factor) * ao; // la noche no queda negra del todo
	out_specular = specular * light_energy * day_factor;
}

#endif // PLANET_LIGHTING_INC
