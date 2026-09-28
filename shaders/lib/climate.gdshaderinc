// =============================================================================
//  climate.gdshaderinc
//  Campo de frío del planeta, el mismo en todos los shaders (terreno, rocas, árboles, hierba,
//  agua), en los grafos de vegetación (ClimateGraph) y en CPU (ClimateField). Así la
//  nieve del suelo, la de las copas, el hielo del mar y dónde crece cada planta coinciden.
//
//  frío = |latitud| + gradiente · altura + dos octavas de ruido OpenSimplex2 (grados).
//  La altura suma frío como si fuera latitud: la alta montaña sale sola, sin bioma aparte.
//  Lo empuja Planet.setup_shader_parameters() desde "climate_settings" del JSON del planeta; los
//  planetas sin ese bloque no lo tocan y aquí se queda apagado (climate_shape.w = 0).
//
//  Las funciones reciben la posición RELATIVA al centro del planeta: cada shader la calcula con
//  su convención (terreno: center - u_world_offset; objetos: planet_position).
// =============================================================================
#ifndef CLIMATE_INC
#define CLIMATE_INC

#include "res://shaders/lib/fnl_simplex.gdshaderinc"

// x = radio nominal, y = grados de frío por metro de altura, z = altura (m sobre el radio) desde
// la que empieza a enfriar, w = 1 si el planeta tiene clima.
global uniform vec4 climate_shape;
// x = frecuencia de la octava ancha, y = su amplitud (grados), z/w = lo mismo de la fina.
global uniform vec4 climate_noise;
// Semillas de las dos octavas (se guardan como float: los globales son vec4 o escalares).
global uniform vec2 climate_seeds;
// x = frío al que empieza a cuajar la nieve, y = frío con el suelo nevado, z = frío del casquete
// (hielo glaciar en las laderas), w = frío del casquete pleno.
global uniform vec4 climate_snow;
// Hielo marino: x = |latitud| a la que empieza, y = |latitud| con el mar helado, z = grados que se
// adelanta junto a la costa (ríos, fiordos y bahías se hielan antes), w = alcance de ese adelanto (m).
global uniform vec4 climate_sea_ice;
// Nieve reciente del temporal, 0..1 (WeatherController). Baja la cota de nieve CLIMATE_FRESH_SHIFT grados.
global uniform float climate_fresh_snow;

#define CLIMATE_FRESH_SHIFT 9.0
// Fuera de esta banda de altura la posición no es de este planeta (la luna comparte shaders).
#define CLIMATE_MAX_ALTITUDE 4000.0

bool climate_active(vec3 local) {
	return climate_shape.w > 0.5 && abs(length(local) - climate_shape.x) < CLIMATE_MAX_ALTITUDE;
}

// |latitud| en grados.
float climate_latitude(vec3 local) {
	return degrees(asin(clamp(abs(local.y) / max(length(local), 0.001), 0.0, 1.0)));
}

// Frío en grados de latitud equivalente. -100 donde no hay clima.
float climate_coldness(vec3 local) {
	if (!climate_active(local)) {
		return -100.0;
	}
	float height = length(local) - climate_shape.x;
	float cold = climate_latitude(local) + climate_shape.y * max(height - climate_shape.z, 0.0);
	cold += fast_noise_lite_open_simplex2_3d(local, climate_noise.x, int(climate_seeds.x)) * climate_noise.y;
	cold += fast_noise_lite_open_simplex2_3d(local, climate_noise.z, int(climate_seeds.y)) * climate_noise.w;
	return cold;
}

// El mismo frío para quien solo lo quiere para la nieve: si ni con todo el ruido a favor ni con la
// nevada que cae ahora llega a la cota, devuelve el frío sin ruido y se ahorra las dos octavas. Es lo
// que usan la hierba y los árboles: en el trópico y la zona templada baja no pagan nada. `margin`:
// grados que el llamante aún suma al frío (las manchas de nieve del terreno); 0 en los objetos.
float climate_snow_coldness(vec3 local, float margin) {
	if (!climate_active(local)) {
		return -100.0;
	}
	float height = length(local) - climate_shape.x;
	float cold = climate_latitude(local) + climate_shape.y * max(height - climate_shape.z, 0.0);
	float reach = abs(climate_noise.y) + abs(climate_noise.w) + climate_fresh_snow * CLIMATE_FRESH_SHIFT + margin;
	if (cold + reach < climate_snow.x) {
		return cold;
	}
	cold += fast_noise_lite_open_simplex2_3d(local, climate_noise.x, int(climate_seeds.x)) * climate_noise.y;
	cold += fast_noise_lite_open_simplex2_3d(local, climate_noise.z, int(climate_seeds.y)) * climate_noise.w;
	return cold;
}

// Frío para la nieve de los objetos (hierba, árboles, rocas): solo la octava ancha del ruido. La
// fina mueve ±1,5 grados en una rampa de nieve de 13 y se evaluaba en cada vértice de cada mata.
float climate_snow_coldness(vec3 local) {
	if (!climate_active(local)) {
		return -100.0;
	}
	float height = length(local) - climate_shape.x;
	float cold = climate_latitude(local) + climate_shape.y * max(height - climate_shape.z, 0.0);
	if (cold + abs(climate_noise.y) + climate_fresh_snow * CLIMATE_FRESH_SHIFT < climate_snow.x) {
		return cold;
	}
	return cold + fast_noise_lite_open_simplex2_3d(local, climate_noise.x, int(climate_seeds.x)) * climate_noise.y;
}

// Cuánta nieve admite el clima en ese frío (0..1), con la nieve reciente del temporal.
float climate_snow_cover(float cold) {
	float shift = climate_fresh_snow * CLIMATE_FRESH_SHIFT;
	return smoothstep(climate_snow.x - shift, climate_snow.y - shift, cold);
}

// 0..1: casquete polar o cumbre helada.
float climate_glacier(float cold) {
	return smoothstep(climate_snow.z, climate_snow.w, cold);
}

// Nieve posada sobre una superficie: cubre las caras que miran al cielo y resbala de las
// empinadas. facing = dot(normal, arriba del planeta). Con más frío cuaja en caras más verticales.
float climate_surface_snow(float cover, float facing, float glacier) {
	float lower = mix(0.55, 0.15, glacier);
	return cover * smoothstep(lower, lower + 0.3, facing);
}

float climate_hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// Ruido de valor 3D barato en [0, 1], para el grano del borde de la nieve sobre los objetos.
float climate_value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(climate_hash(i), climate_hash(i + vec3(1, 0, 0)), f.x),
			mix(climate_hash(i + vec3(0, 1, 0)), climate_hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(climate_hash(i + vec3(0, 0, 1)), climate_hash(i + vec3(1, 0, 1)), f.x),
			mix(climate_hash(i + vec3(0, 1, 1)), climate_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// Nieve posada sobre un objeto (roca, corteza, tronco): la de climate_surface_snow con el borde
// roto por un grano de pocos centímetros, para que no sea una línea a nivel. local = posición
// relativa al planeta (estable con el origen flotante).
float climate_object_snow(float cover, float glacier, float facing, vec3 local) {
	float grain = climate_value_noise(local * 2.3) * 0.6 + climate_value_noise(local * 9.0) * 0.4;
	return climate_surface_snow(cover, facing + (grain - 0.5) * 0.45, glacier);
}

// Color de la nieve sobre objetos: algo azulada, como la del suelo a la sombra del cielo.
const vec3 CLIMATE_SNOW_ALBEDO = vec3(0.86, 0.89, 0.93);
// Escarcha del casquete: velo claro y frío sobre lo que no cubre la nieve.
const vec3 CLIMATE_RIME_ALBEDO = vec3(0.66, 0.74, 0.82);

// Hielo marino (0..1) en el agua. Solo latitud y distancia a la costa: el agua lo evalúa decenas de
// veces por píxel en la niebla submarina y no puede pagar el ruido. shore_dist < 0 = sin dato.
// WaterHeightSampler / ClimateField.sea_ice son la réplica en CPU.
float climate_sea_ice_at(vec3 local, float shore_dist) {
	if (climate_shape.w < 0.5) {
		return 0.0;
	}
	vec3 d = normalize(local);
	float lat = degrees(asin(clamp(abs(d.y), 0.0, 1.0)));
	// Borde del banco de hielo ondulado en longitud, sin ruido: lenguas y bahías de cientos de km.
	float lon = atan(d.z, d.x);
	lat += sin(lon * 7.0) * 1.6 + sin(lon * 17.0 + 1.3) * 0.7;
	float coast = shore_dist >= 0.0
		? (1.0 - smoothstep(climate_sea_ice.w * 0.25, climate_sea_ice.w, shore_dist)) * climate_sea_ice.z
		: 0.0;
	return smoothstep(climate_sea_ice.x, climate_sea_ice.y, lat + coast);
}

#endif
