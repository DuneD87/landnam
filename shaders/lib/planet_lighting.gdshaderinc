// =============================================================================
//  planet_lighting.gdshaderinc
//  Fuente de verdad ÚNICA de la iluminación planetaria custom.
//
//  Reúne lo que antes estaba duplicado en grass_wind y transparent_material_shader:
//    1. Difuso Lambert
//    2. Especular GGX/Cook-Torrance (respeta metallic/roughness, estilo StandardMaterial3D)
//    3. Translucencia / SSS (luz a contraluz que atraviesa el material)
//    4. Fresnel / Rim
//    5. Horizonte del planeta POR LUZ (terminador día/noche del sol y de la luna)
//
//  El relleno ambiente ya NO se calcula aquí: lo pone el entorno, que es el cielo del observador
//  (SkyLighting → pase de cubemap de space_sky.gdshader), una sola vez por fragmento, con AO y
//  sin pasar por la sombra de ninguna luz. El de antes se sumaba dentro de light() —una vez por
//  luz direccional, así que con la luna contaría doble— y multiplicado por ATTENUATION: a la sombra
//  de un árbol el follaje se quedaba sin difuso Y sin ambiente, negro puro. Tampoco era un
//  hemisferio de cielo: mezclaba sus colores con la altura del SOL, y de día salía el del suelo.
//
//  IMPORTANTE (bug de compilación): la función NO lee los varyings como globales.
//  Acceder a un `varying` dentro de una función auxiliar llamada desde light()
//  cuelga el compilador de Godot. Por eso los varyings se pasan como parámetros y
//  solo se leen DIRECTAMENTE dentro de light().
//
//  Uso desde un shader spatial:
//    #include "res://shaders/lib/planet_lighting.gdshaderinc"
//
//    En vertex():
//      vertex_position_global = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; // tras viento, si lo hay
//      planet_normal          = normalize(vertex_position_global - planet_position);
//
//    En light():
//      vec3 up_view = normalize((VIEW_MATRIX * vec4(planet_normal, 0.0)).xyz);
//      vec3 d, s;
//      compute_planet_light(NORMAL, VIEW, LIGHT, LIGHT_COLOR, ATTENUATION,
//          ALBEDO, METALLIC, ROUGHNESS, specular_uniform,
//          up_view, LIGHT_IS_DIRECTIONAL, 1.0, d, s);
//      DIFFUSE_LIGHT  += d;   // el motor multiplica DIFFUSE_LIGHT por ALBEDO
//      SPECULAR_LIGHT += s;   // opcional (grass/transparent lo omiten)
//
//  El planeta alimenta planet_position al cambiar el centro. La dirección y el
//  color de cada luz llegan por LIGHT/LIGHT_COLOR en light().
// =============================================================================
#ifndef PLANET_LIGHTING_INC
#define PLANET_LIGHTING_INC

// --- Alimentados por el planeta ---
uniform vec3  planet_position;

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

// Visibilidad de una luz direccional sobre el horizonte local del planeta. Va POR LUZ: el sol y la
// luna salen y se ponen cada uno por su lado. Estrecha a propósito: la radiancia de cada luz ya se
// apaga con su propio ocaso en el horizonte del observador (SkyLighting); esto solo separa el día
// de la noche en la vegetación lejana y corta la luz que el planeta tiene delante. El terminador
// ancho de antes (±11°, solo del sol) apagaba la vegetación mucho antes que el suelo que pisaba.
const float PLANET_TERMINATOR_SOFTNESS = 0.035;

float planet_light_visibility(vec3 up_view, vec3 L) {
	return smoothstep(-PLANET_TERMINATOR_SOFTNESS, PLANET_TERMINATOR_SOFTNESS, dot(up_view, L));
}

// out_diffuse  -> DIFFUSE_LIGHT  (el motor lo multiplica por ALBEDO)
// out_specular -> SPECULAR_LIGHT (NO se multiplica por ALBEDO)
//
// is_directional distingue el sol y la luna (luces direccionales) de las luces locales
// (antorchas, hogueras...). El horizonte del planeta solo tiene sentido para las primeras;
// aplicarlo a una luz local la apagaría según hacia dónde quede. Pasa LIGHT_IS_DIRECTIONAL
// desde el light() de cada shader.
// El parámetro `detail` (0..1) escala y GATEA la translucencia/rim: cuando es 0
// (p.ej. follaje lejano) se salta esos pow/normalize por completo. Pasar 1.0
// para conservar el comportamiento original.
void compute_planet_light(
		vec3 N, vec3 V, vec3 L, vec3 light_color, float attenuation,
		vec3 albedo, float metallic, float roughness, float specular_amount,
		vec3 up_view, bool is_directional, float detail,
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

	// === 3+4. Translucencia / SSS y Fresnel / Rim (view-dependent, coste alto).
	// Solo se calcula si detail > 0; con detail bajo el follaje lejano se ahorra
	// 3 pow + 1 normalize por fragmento. La rama es coherente (detail varía suave).
	vec3 translucency = vec3(0.0);
	vec3 rim = vec3(0.0);
	if (detail > 0.001) {
		vec3  back_light  = normalize(-L + N * 0.3);
		float VdotBL      = clamp(dot(V, back_light), 0.0, 1.0);
		float back_factor = pow(clamp(-dot(N, L), 0.0, 1.0), 6.0);
		float sss = pow(VdotBL, translucency_power) * translucency_strength * back_factor;
		translucency = sss * translucency_color.rgb * detail;

		float fresnel = pow(1.0 - NdotV, 3.0);
		rim = vec3(fresnel * rim_strength / PI) * detail;
	}

	// === 5. Horizonte del planeta, por luz ===
	float horizon = is_directional ? planet_light_visibility(up_view, L) : 1.0;

	out_diffuse  = (diffuse + translucency + rim) * light_energy * horizon;
	out_specular = specular * light_energy * horizon;
}

#endif // PLANET_LIGHTING_INC
