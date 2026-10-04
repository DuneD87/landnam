// =============================================================================
//  season.gdshaderinc
//  Estaciones de la vegetación. La fecha y la estación de cada sitio están en
//  season_calendar.gdshaderinc (lo incluye climate.gdshaderinc, que con él baja la cota de nieve en
//  invierno). scripts/planet/seasons.gd es la réplica en CPU.
//
//  Hoja caduca (todos los árboles Branching): brota en primavera con la hoja tierna, madura,
//  amarillea y enrojece en otoño y cae al terminar el otoño. Cada tarjeta de ramillete lleva su
//  propio paso (COLOR.a, aleatorio por tarjeta): la copa cambia a manchas y se aclara poco a poco.
//  La hoja se separa de la ramilla por el color de la textura (season_leaf_mask): sin hoja queda
//  la madera de la ramilla dibujada en la tarjeta. Los frutales florecen al brotar.
//
//  Pradera (hierba, sotobosque herbáceo, textura de pradera del terreno): verde tierno en
//  primavera, se agosta en otoño y queda parda en invierno (season_meadow_state). Las flores del
//  sotobosque se abren en la ventana de su especie (season_bloom).
// =============================================================================
#ifndef SEASON_INC
#define SEASON_INC

#include "res://shaders/lib/climate.gdshaderinc"

// Calendario de la hoja caduca en fase local (0 = equinoccio de primavera, 0,25 = solsticio de
// verano, 0,5 = equinoccio de otoño, 0,75 = solsticio de invierno) en el frío de referencia. Con
// 8 días por estación, 0,03 de fase es un día.
#define SEASON_BUDBURST 0.03
// Del primer brote a la copa entera con hoja.
#define SEASON_LEAF_OUT 0.08
// De la copa entera a la hoja madura (la tierna es más clara y amarilla).
#define SEASON_FLUSH 0.12
// Primeras hojas amarillas.
#define SEASON_AUTUMN 0.47
// De la primera hoja amarilla a la última en el suelo: el invierno empieza pelado.
#define SEASON_FALL 0.27
// Frío (grados de latitud equivalente, como climate_coldness) del calendario de arriba. Cada
// grado más de frío retrasa la primavera y adelanta el otoño SEASON_COLD_SHIFT de fase: la montaña
// y el norte amarillean antes.
#define SEASON_COLD_REF 25.0
#define SEASON_COLD_SHIFT 0.003
// Reparto entre tarjetas, en progreso de otoño: la primera en amarillear empieza este tanto antes
// que la última.
#define SEASON_CARD_SPREAD 0.5
// Progreso de otoño de una tarjeta (0..) en que cae su hoja.
#define SEASON_DROP 0.9
// Adelanto o retraso de cada árbol (fase, de punta a punta): tree_seed(base, 71u) en follaje,
// corteza e impostor, para que los tres vayan a la par.
#define SEASON_TREE_JITTER 0.03
// Manchas de ruido por ancho de vista del impostor que hacen de tarjetas.
#define SEASON_IMPOSTOR_CELLS 14.0
// Sin hoja, la copa deja de dar sombra a sus ramas: la oclusión horneada del interior de la copa
// (corteza y ramillas) se aclara esta parte.
#define SEASON_BARE_AO_LIFT 0.6
// Desplazamiento de mip de la muestra borrosa de season_leaf_mask_wide.
#define SEASON_MASK_BLUR_BIAS 2.5

const vec3 SEASON_LUMA = vec3(0.2126, 0.7152, 0.0722);
// Hoja tierna: más clara y más amarilla que la madura.
const vec3 SEASON_YOUNG_TINT = vec3(1.3, 1.22, 0.62);

// Pradera, en fase local desde que reverdece (SEASON_MEADOW_GREENUP, con el frío como los árboles):
// reverdece en SEASON_MEADOW_GREENUP_TIME, está tierna hasta mediados de primavera, se seca un poco
// al final del verano (SEASON_MEADOW_SUMMER_DRY) y se agosta del todo en otoño, en
// SEASON_MEADOW_AUTUMN_TIME desde SEASON_AUTUMN.
#define SEASON_MEADOW_GREENUP 0.0
#define SEASON_MEADOW_GREENUP_TIME 0.08
#define SEASON_MEADOW_SUMMER_DRY 0.25
#define SEASON_MEADOW_AUTUMN_TIME 0.25
// Paja del otoño y pardo del invierno (lineal, el tono: la luz la pone cada texel).
const vec3 SEASON_STRAW = vec3(0.55, 0.42, 0.14);
const vec3 SEASON_DORMANT = vec3(0.42, 0.31, 0.19);
// Verde tierno de primavera, multiplicando.
const vec3 SEASON_FRESH_TINT = vec3(0.95, 1.1, 0.74);
// Blanco de los pétalos de los frutales (lineal).
const vec3 SEASON_BLOSSOM_WHITE = vec3(0.86, 0.85, 0.82);

// Retraso de la primavera (y adelanto del otoño) por el frío del sitio, en fase.
float season_cold_shift(vec3 local) {
	if (!climate_active(local)) {
		return 0.0;
	}
	float cold = climate_latitude(local)
		+ climate_shape.y * max(length(local) - climate_shape.x - climate_shape.z, 0.0);
	return clamp((cold - SEASON_COLD_REF) * SEASON_COLD_SHIFT, -0.03, 0.06);
}

// Hoja caduca de un árbol con base en `local` (relativa al centro del planeta):
// x = edad (0 sin hoja, 0..1 brotando, 1..2 madurando, 2 adulta),
// y = otoño (0 verde .. 1 sin hoja). jitter: adelanto del árbol, en fase. spring_shift: adelanto
// (negativo) o retraso de la brotación de la especie (el almendro florece a finales del invierno).
vec2 season_leaf_state(vec3 local, float jitter, float spring_shift) {
	float strength = season_strength(local);
	if (strength <= 0.0 || (season_debug_off & SEASON_OFF_LEAVES) != 0) {
		return vec2(2.0, 0.0);
	}
	float shift = season_cold_shift(local);
	float spring = SEASON_BUDBURST + shift + spring_shift;
	// Tiempo desde la brotación: con la brotación antes del equinoccio (spring < 0) da la vuelta.
	float t = fract(season_local_phase(local) + jitter - spring);
	float autumn = SEASON_AUTUMN - shift - spring;
	vec2 state = vec2(0.0);
	if (t < autumn) {
		state.x = clamp(t / SEASON_LEAF_OUT, 0.0, 1.0)
			+ clamp((t - SEASON_LEAF_OUT) / SEASON_FLUSH, 0.0, 1.0);
	} else {
		float fall = (t - autumn) / SEASON_FALL;
		state = fall < 1.0 ? vec2(2.0, fall) : vec2(0.0);
	}
	return vec2(mix(2.0, state.x, strength), state.y * strength);
}

// Flor de los frutales (0..1) por la edad de su hoja: la tarjeta recién brotada está en flor y la
// flor da paso a la hoja tierna.
float season_blossom(float age) {
	return age > 0.0 ? 1.0 - smoothstep(0.9, 1.5, age) : 0.0;
}

// Pradera en `local`: x = sequedad (0 verde .. 1 parda del invierno), y = verdor tierno de
// primavera (0..1). Sin estaciones, (0, 0): el verano.
vec2 season_meadow_state(vec3 local) {
	float strength = season_strength(local);
	if (strength <= 0.0 || (season_debug_off & SEASON_OFF_MEADOW) != 0) {
		return vec2(0.0);
	}
	float shift = season_cold_shift(local);
	float t = fract(season_local_phase(local) - SEASON_MEADOW_GREENUP - shift);
	float autumn = SEASON_AUTUMN - shift - (SEASON_MEADOW_GREENUP + shift);
	float dry = 1.0 - smoothstep(0.0, SEASON_MEADOW_GREENUP_TIME, t);
	dry = max(dry, smoothstep(0.3, autumn, t) * SEASON_MEADOW_SUMMER_DRY);
	if (t >= autumn) {
		dry = mix(SEASON_MEADOW_SUMMER_DRY, 1.0, smoothstep(autumn, autumn + SEASON_MEADOW_AUTUMN_TIME, t));
	}
	float fresh = smoothstep(0.0, 0.06, t) * (1.0 - smoothstep(0.18, 0.32, t));
	return vec2(dry, fresh) * strength;
}

// Color de la pradera en un estado de season_meadow_state: hacia la paja en otoño y el pardo en
// invierno, conservando la luz relativa de cada texel (la paja algo más clara que la hoja verde);
// más tierna y amarillenta en primavera.
vec3 season_meadow_color(vec3 c, vec2 state) {
	float luma = dot(c, SEASON_LUMA);
	vec3 straw = SEASON_STRAW * (luma / dot(SEASON_STRAW, SEASON_LUMA)) * 1.15;
	vec3 dormant = SEASON_DORMANT * (luma / dot(SEASON_DORMANT, SEASON_LUMA));
	vec3 dry = mix(straw, dormant, smoothstep(0.6, 1.0, state.x));
	vec3 color = mix(c, dry, smoothstep(0.0, 0.85, state.x) * 0.9);
	return color * mix(vec3(1.0), SEASON_FRESH_TINT, state.y);
}

// Floración de una especie (0..1): ventana de ancho total `width` centrada en `center` (fase local,
// 0 = equinoccio de primavera), retrasada por el frío. Sin estaciones, en flor todo el año.
float season_bloom(vec3 local, float center, float width) {
	float strength = season_strength(local);
	if (strength <= 0.0) {
		return 1.0;
	}
	float d = abs(fract(season_local_phase(local) - season_cold_shift(local) - center + 0.5) - 0.5);
	return mix(1.0, 1.0 - smoothstep(width * 0.3, width * 0.5, d), strength);
}

// Color de una flor (lineal) con la luz relativa del texel de hoja que sustituye.
vec3 season_flower_color(vec3 c, vec3 flower, float luma_ref) {
	return flower * clamp(dot(c, SEASON_LUMA) / max(luma_ref, 0.001), 0.5, 1.6);
}

// Parte de las tarjetas que tienen hoja (0..1) en un estado de season_leaf_state.
float season_leaf_cover(vec2 state) {
	float dropped = clamp((state.y * (1.0 + SEASON_CARD_SPREAD) - SEASON_DROP) / SEASON_CARD_SPREAD, 0.0, 1.0);
	return clamp(state.x, 0.0, 1.0) * (1.0 - dropped);
}

// Hoja de una tarjeta con aleatorio r en [0, 1): x = 1 si tiene hoja, y = etapa de otoño (0 verde
// .. 1 seca, justo antes de caer), z = hoja tierna (0..1). Brota en otro orden del que cae.
vec3 season_card(vec2 state, float r) {
	float grown = fract(r * 7.31 + 0.137) < state.x ? 1.0 : 0.0;
	float progress = state.y * (1.0 + SEASON_CARD_SPREAD) - (1.0 - r) * SEASON_CARD_SPREAD;
	float has_leaf = progress <= SEASON_DROP ? grown : 0.0;
	return vec3(has_leaf, clamp(progress / SEASON_DROP, 0.0, 1.0), clamp(2.0 - state.x, 0.0, 1.0));
}

// Hoja (1) o madera (0) de un texel de ramillete por su color (lineal): la hoja es verde o verde
// amarillenta y saturada; la ramilla es gris, parda o violácea (con más rojo que verde).
// edges (leaf_mask_edges de cada especie): x..y = saturación, z..w = (verde − rojo) / máximo. Por
// defecto (0,45, 0,6, −0,25, −0,05), medidos en las ramitas de manzano, almendro, abedul y picea. El
// pino y el olivo, de hoja poco saturada (acícula oscura, hoja plateada), bajan la saturación y se
// apoyan en el matiz: su madera es más roja que verde.
float season_leaf_mask(vec3 c, vec4 edges) {
	float top = max(max(c.r, c.g), max(c.b, 0.0001));
	float saturation = (top - min(min(c.r, c.g), c.b)) / top;
	return smoothstep(edges.x, edges.y, saturation) * smoothstep(edges.z, edges.w, (c.g - c.r) / top);
}

// La misma máscara ensanchada con una muestra borrosa de la textura (blurred, unos mips más
// pequeña): el contorno oscuro de cada hoja y los peciolos pálidos no son ni verdes ni pardos y,
// sin hoja, quedaban como un encaje de restos. Lo que es claramente madera (más rojo que verde) no
// se ensancha.
float season_leaf_mask_wide(vec3 c, vec3 blurred, vec4 edges) {
	float top = max(max(c.r, c.g), max(c.b, 0.0001));
	float wood = smoothstep(0.0, 0.06, (c.r - c.g) / top);
	return max(season_leaf_mask(c, edges), season_leaf_mask(blurred, edges) * (1.0 - wood));
}

// Color de una hoja verde `c` (lineal) según su tarjeta (season_card): tierna en primavera y, en
// otoño, del verde al primer color (early), al de pleno otoño (late) y al de la hoja seca
// (withered). reference: la hoja verde media de la textura, x = luminancia, y = cromaticidad verde
// (g / (r + g + b)), las dos en lineal. Los colores de otoño son los de esa hoja media: cada texel
// conserva su luz relativa, y las hojas más amarillas que la media van algo por delante.
vec3 season_leaf_color(vec3 c, vec3 card, vec3 early, vec3 late, vec3 withered, vec2 reference) {
	vec3 color = c * mix(vec3(1.0), SEASON_YOUNG_TINT, card.z);
	if (card.y <= 0.0) {
		return color;
	}
	float chroma = c.g / max(c.r + c.g + c.b, 0.0001);
	float stage = clamp(card.y + (reference.y - chroma) * 3.0 * smoothstep(0.0, 0.15, card.y), 0.0, 1.0);
	vec3 target = mix(early, late, smoothstep(0.3, 0.75, stage));
	target = mix(target, withered, smoothstep(0.8, 1.0, stage));
	vec3 autumn = target * clamp(dot(c, SEASON_LUMA) / max(reference.x, 0.001), 0.35, 2.0);
	return mix(color, autumn, smoothstep(0.0, 0.3, stage));
}

#endif
