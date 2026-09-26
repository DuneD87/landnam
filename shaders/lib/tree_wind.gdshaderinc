// =============================================================================
//  tree_wind.gdshaderinc
//  Viento jerárquico de los árboles del generador Branching (Tree3D). Lee los datos
//  que hornea el generador en cada vértice:
//    COLOR.g  fase de la rama principal     COLOR.b  peso de rama (0 tronco, 1 puntas)
//    COLOR.a  1 madera / tarjeta: aleatorio por tarjeta en [0, 0.9)
//    UV2.x    (altura / altura del árbol)^2
//    UV2.y    tarjeta: posición a lo largo (aleteo); madera: nivel / 2
//  Tres capas: el tronco se inclina a favor del viento, cada rama principal oscila con su
//  propia fase (sus ramillas y tarjetas heredan la misma, así que no se despegan) y las
//  tarjetas aletean a lo largo de su normal. Madera y hojas usan la misma función: la
//  rama y sus ramilletes se mueven juntos también en el pase de sombras.
//
//  planet.gd empuja wind_direction y wind_speed cada frame. NO renombrar.
// =============================================================================
#ifndef TREE_WIND_INC
#define TREE_WIND_INC

uniform vec3 wind_direction = vec3(1.0, 0.0, 0.0);
uniform float wind_speed : hint_range(0.0, 10.0, 0.01) = 0.3;
// Inclinación de la copa (fracción de la altura) por unidad de viento.
uniform float trunk_sway : hint_range(0.0, 0.2, 0.001) = 0.03;
// Desplazamiento de las puntas de rama (m) por unidad de viento.
uniform float branch_sway : hint_range(0.0, 2.0, 0.01) = 0.45;
// Aleteo de las tarjetas (m) por unidad de viento.
uniform float leaf_flutter : hint_range(0.0, 1.0, 0.01) = 0.12;
uniform float wind_frequency : hint_range(0.1, 4.0, 0.01) = 1.0;

uint tree_hash(uint x) {
	x ^= x >> 16u;
	x *= 2146121517u;
	x ^= x >> 15u;
	x *= 2221713035u;
	return x ^ (x >> 16u);
}

// Semilla estable por árbol a partir de su posición relativa al planeta (no depende de
// INSTANCE_ID, que cambia al reagrupar los MultiMesh de un bloque).
float tree_seed(vec3 relative_base, uint salt) {
	ivec3 cell = ivec3(floor(relative_base * 2.0));
	uint id = tree_hash(uint(cell.x) ^ salt) ^ tree_hash(uint(cell.y) + 2654435769u)
		^ tree_hash(uint(cell.z) + 2246822507u);
	return float(tree_hash(id)) * (1.0 / 4294967296.0);
}

// Vertical del planeta en la base. Sin planet_position (horneado de impostores, antes del
// primer empuje del planeta) la base coincide con el centro y normalize() daba NaN: el
// árbol entero desaparecía.
vec3 tree_up(vec3 relative_base) {
	float len = length(relative_base);
	return len > 1.0 ? relative_base / len : vec3(0.0, 1.0, 0.0);
}

// Desplazamiento en espacio LOCAL del vértice. up: vertical del planeta en la base.
vec3 tree_wind_offset(vec3 vertex, vec3 normal, vec4 color, vec2 uv2, mat4 model, vec3 up,
		float seed, float time) {
	vec3 wt = wind_direction - up * dot(wind_direction, up);
	wt /= max(length(wt), 0.0001);
	float t = time * wind_frequency;
	float strength = wind_speed;
	float scale = length(model[1].xyz);

	// Tronco: se inclina a favor del viento y oscila despacio alrededor de esa inclinación.
	float gust = sin(t * 0.9 + seed * 6.2832) * 0.6 + sin(t * 0.37 + seed * 2.1) * 0.4;
	float height = max(vertex.y, 0.0) * scale;
	vec3 offset = wt * (sqrt(uv2.x) * height * trunk_sway * strength * (0.65 + 0.35 * gust));

	// Rama: fase propia heredada por sus ramas y tarjetas.
	float phase = color.g * 6.2832 + seed * 6.2832;
	float branch = sin(t * 1.9 + phase) * 0.7 + sin(t * 3.3 + phase * 1.7) * 0.3;
	offset += (wt * (0.55 + 0.45 * branch) + up * (0.3 * branch))
		* (branch_sway * color.b * strength * scale);

	// Aleteo de la tarjeta a lo largo de su normal, más fuerte en la punta.
	float leaf = (color.a < 0.95 ? 1.0 : 0.0) * uv2.y;
	if (leaf > 0.0) {
		float h = float(tree_hash(floatBitsToUint(vertex.x * 7.1 + vertex.z * 3.3))) * (1.0 / 4294967296.0);
		vec3 wn = normalize((model * vec4(normal, 0.0)).xyz);
		offset += wn * (sin(t * 6.5 + h * 6.2832 + phase) * leaf_flutter * strength * leaf * scale);
	}

	// A local sin inverse(): la base es ortogonal con escala (como en grass_wind).
	return vec3(
		dot(model[0].xyz, offset) / dot(model[0].xyz, model[0].xyz),
		dot(model[1].xyz, offset) / dot(model[1].xyz, model[1].xyz),
		dot(model[2].xyz, offset) / dot(model[2].xyz, model[2].xyz));
}

// --- Pase de sombras aligerado -----------------------------------------------------------
// Las sombras de los árboles eran ~2 ms de los 7 del bosque: cada árbol se dibuja otra vez en
// una o dos cascadas. En el pase de sombras se descarta una fracción de tarjetas enteras (más
// cuanto más lejos, donde la cascada es gruesa) y las ramas secundarias lejos de la cámara.
uniform float shadow_card_keep_near : hint_range(0.0, 1.0, 0.01) = 0.7;
uniform float shadow_card_keep_far : hint_range(0.0, 1.0, 0.01) = 0.25;
uniform float shadow_thin_start = 25.0;
uniform float shadow_thin_end = 100.0;
uniform float shadow_twig_wood_distance = 12.0;

// true si el vértice no debe proyectar sombra (se colapsa).
bool tree_shadow_skip(vec4 color, vec2 uv2, float camera_distance) {
	if (color.a < 0.95) {
		float keep = mix(shadow_card_keep_near, shadow_card_keep_far,
			smoothstep(shadow_thin_start, shadow_thin_end, camera_distance));
		return color.a >= keep * 0.9;
	}
	return uv2.y > 0.75 && camera_distance > shadow_twig_wood_distance;
}

// --- Relevo entre bandas del instancer (planet.gd::_register_tree_bands) ---------------
// Distancia de la base del árbol a la cámara del jugador (también en el pase de sombras,
// como la hierba). 0/0 desactiva cada lado.
uniform float fade_in_start = 0.0;
uniform float fade_in_end = 0.0;
uniform float fade_out_start = 0.0;
uniform float fade_out_end = 0.0;

// x: fundido de entrada, y: de salida (1 = visible). Por árbol, desde su base.
vec2 tree_band_fades(vec3 base_world, mat4 main_cam_inv_view) {
	float d = distance(base_world, main_cam_inv_view[3].xyz);
	float fade_out = fade_out_end > fade_out_start ? 1.0 - smoothstep(fade_out_start, fade_out_end, d) : 1.0;
	float fade_in = fade_in_end > fade_in_start ? smoothstep(fade_in_start, fade_in_end, d) : 1.0;
	return vec2(fade_in, fade_out);
}

// Tramado estable en pantalla. La entrada usa el ruido invertido: el LOD que sale y el que
// entra se reparten los píxeles de la misma copa sin solaparse ni dejar huecos (con el mismo
// ruido, a mitad del relevo los dos cubrían los mismos píxeles y el resto quedaba vacío).
bool tree_band_discard(vec2 fades, vec2 frag) {
	if (fades.x >= 0.999 && fades.y >= 0.999) {
		return false;
	}
	float noise = fract(52.9829189 * fract(dot(frag, vec2(0.06711056, 0.00583715))));
	return fades.y <= noise || fades.x <= 1.0 - noise;
}

#endif // TREE_WIND_INC
