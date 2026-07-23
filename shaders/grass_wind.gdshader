shader_type spatial;
// Hierba low-poly opaca con viento en espacio mundo, pensada para instanciar con
// VoxelInstancer (MultiMesh) sobre un planeta esférico.
//
// Integración: el planeta (planet.gd::_update_planet) escribe cada frame
//   light_direction, planet_position, wind_direction, wind_speed
// sobre cada ShaderMaterial de la malla. NO cambiar esos nombres.
//
// Requisito del asset: el pivote del modelo debe estar en la BASE de la brizna
// (origen de la instancia = punto que toca el suelo). El resto es tolerante a la
// orientación/escala locales porque el "arriba" se deriva del centro del planeta.

render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/lib/planet_lighting.gdshaderinc"

// --- Color (el modelo no tiene textura: gradiente base->punta) ---
uniform vec4 base_color : source_color = vec4(0.06, 0.30, 0.04, 1.0); // raíz, más oscuro
uniform vec4 tip_color  : source_color = vec4(0.20, 0.65, 0.10, 1.0); // punta, más claro

// --- Geometría del doblez ---
uniform float grass_height : hint_range(0.05, 5.0, 0.01) = 1.0; // altura de la brizna en metros mundo
uniform float bend_curve   : hint_range(1.0, 6.0, 0.1)   = 2.0; // >1 deja la base más rígida

// --- Viento (alimentados por el planeta) ---
uniform vec3  wind_direction = vec3(1.0, 0.0, 0.0);
uniform float wind_speed : hint_range(0.0, 10.0, 0.01) = 1.0;
uniform float wind_amplitude : hint_range(0.0, 1.0, 0.001) = 0.15; // cuánto se dobla la punta (fracción de altura)

// --- Capa 1: ráfaga (onda lenta que viaja por el campo) ---
uniform float gust_scale : hint_range(0.0, 2.0, 0.001) = 0.15; // frecuencia espacial de la ola
uniform float gust_speed : hint_range(0.0, 5.0, 0.01)  = 1.0;  // velocidad de avance de la ola

// --- Capa 2: aleteo (oscilación rápida y pequeña por brizna) ---
uniform float flutter_speed  : hint_range(0.0, 20.0, 0.01) = 6.0;
uniform float flutter_amount : hint_range(0.0, 1.0, 0.01)  = 0.25;

// --- Iluminación planetaria: los uniforms compartidos viven en planet_lighting.gdshaderinc.
//     Aquí solo el control de especular propio del shader.
uniform float specular_strength : hint_range(0.0, 1.0, 0.01) = 0.15;
uniform float specular_roughness : hint_range(0.0, 1.0, 0.01) = 0.7;

// vertex_position_global y planet_normal se declaran en el include.
varying float height_factor;         // 0 en la base, 1 en la punta

void vertex() {
    // Posiciones en espacio mundo
    vec3 world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec3 base = MODEL_MATRIX[3].xyz;                 // origen de la instancia = base de la brizna
    // "Arriba" radial del planeta en la base de la brizna (independiente de la malla)
    vec3 up = normalize(base - planet_position);

    // Altura del vértice a lo largo del eje radial -> máscara de doblez
    float h = dot(world_vertex - base, up);
    height_factor = clamp(h / grass_height, 0.0, 1.0);
    float mask = pow(height_factor, bend_curve);     // base rígida, punta suelta

    // Viento proyectado al plano tangente del suelo (dobla de lado, no hacia el planeta)
    vec3 wt = wind_direction - up * dot(wind_direction, up);
    float wlen = length(wt);
    wt = (wlen > 1e-4) ? wt / wlen : vec3(0.0);

    // Capa 1: ráfaga que viaja por el campo (fase según posición de la instancia)
    float gust = sin(dot(base, wt) * gust_scale - TIME * wind_speed * gust_speed);
    // Capa 2: aleteo rápido, desfasado por instancia para que no vayan al unísono
    float seed = dot(base, vec3(12.9898, 78.233, 37.719));
    float flutter = sin(TIME * flutter_speed + seed) * flutter_amount;

    float sway = (gust + flutter) * wind_amplitude * wind_speed * mask * grass_height;

    // Desplazamiento en mundo: lateral + pequeño hundimiento para fingir longitud constante
    vec3 world_offset = wt * sway - up * (sway * sway * 0.5 / max(grass_height, 1e-3));

    // Aplicar SOLO el desplazamiento como VECTOR (w=0). Reconstruir la posición
    // completa (w=1) con inverse() en coords mundo grandes (~45k) pierde precisión
    // en fp32 y revienta la geometría en juego; con w=0 solo se rota/escala un
    // offset pequeño, sin cancelación.
    VERTEX += (inverse(MODEL_MATRIX) * vec4(world_offset, 0.0)).xyz;

    // Datos para fragment/light en espacio mundo
    vertex_position_global = world_vertex + world_offset;
	float day_f;
	vec3 amb;
	compute_planet_vertex_light(vertex_position_global, planet_normal, day_f, amb);
	planet_day_factor = day_f;
	planet_ambient = amb;
    planet_normal = normalize(vertex_position_global - planet_position);
}

void fragment() {
    ALBEDO = mix(base_color.rgb, tip_color.rgb, height_factor);
    ROUGHNESS = specular_roughness;
    SPECULAR = specular_strength;
    if (!FRONT_FACING) {
        NORMAL = -NORMAL; // malla de doble cara
    }
}
void light() {
    // Iluminación planetaria compartida (ver planet_lighting.gdshaderinc).
    // Sin specular para conservar el look original; el difuso es equivalente.
    vec3 d, s;
    compute_planet_light(
		NORMAL, VIEW, LIGHT, LIGHT_COLOR, ATTENUATION,
		ALBEDO, METALLIC, ROUGHNESS, 0.0, 0.0,
		planet_day_factor, planet_ambient, LIGHT_IS_DIRECTIONAL, 1.0, d, s);
    DIFFUSE_LIGHT += d;
}