// Sangre sobre la vegetación (BloodFoliage): hasta 128 salpicaduras en coordenadas canónicas
// (mundo actual + u_world_offset), así que no hay que moverlas con el origen flotante. Van en grupos
// de BLOOD_GROUP_SIZE vecinas, cada grupo con su esfera, y una hoja solo recorre los grupos en cuya
// esfera cae: el coste no crece con cuántas haya en total.
//   blood_splats       fila 0: las salpicaduras, por grupos (el grupo g ocupa g*8 .. g*8+7);
//                      xyz centro, w = radio en milímetros (parte entera, ya encogido al apagarse)
//                      + lo seca que está (parte decimal, 0..0,99). Radio 0 = hueco.
//                      fila 1: la esfera de cada grupo (xyz centro, w radio)
//   blood_splat_count  cuántos grupos hay
//   blood_splat_bounds esfera que abarca todos los grupos: fuera de ella no se mira nada, así que
//                      sin sangre cerca no cuesta nada
// La sangre se calcula en el vertex sobre la posición de la hoja en reposo (antes del viento): va
// pegada a la hoja y se mueve con ella.

const int BLOOD_GROUP_SIZE = 8;

global uniform sampler2D blood_splats;
global uniform int blood_splat_count;
global uniform vec4 blood_splat_bounds;
global uniform vec3 u_world_offset;

// Cuánta sangre le llega a [world_pos] (posición actual) y lo seca que está.
vec2 blood_amount(vec3 world_pos) {
	if (blood_splat_count <= 0) {
		return vec2(0.0);
	}
	vec3 p = world_pos + u_world_offset;
	if (distance(p, blood_splat_bounds.xyz) > blood_splat_bounds.w) {
		return vec2(0.0);
	}
	float amount = 0.0;
	float dry = 0.0;
	for (int g = 0; g < blood_splat_count; g++) {
		vec4 group = texelFetch(blood_splats, ivec2(g, 1), 0);
		if (distance(p, group.xyz) > group.w) {
			continue;
		}
		for (int k = 0; k < BLOOD_GROUP_SIZE; k++) {
			vec4 splat = texelFetch(blood_splats, ivec2(g * BLOOD_GROUP_SIZE + k, 0), 0);
			float radius = floor(splat.w) * 0.001;
			if (radius <= 0.0) {
				break;
			}
			float a = 1.0 - smoothstep(radius * 0.4, radius, distance(p, splat.xyz));
			if (a > amount) {
				amount = a;
				dry = fract(splat.w);
			}
		}
	}
	return vec2(amount, dry);
}

float blood_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float blood_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(blood_hash(i), blood_hash(i + vec2(1.0, 0.0)), u.x),
			mix(blood_hash(i + vec2(0.0, 1.0)), blood_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// A gotas, no la hoja entera: [uv] de la hoja y [seed] de la mata dan un salpicado fijo sobre ella,
// más tupido cuanta más sangre.
float blood_spots(vec2 uv, float seed, float amount) {
	float n = blood_noise(uv * vec2(5.0, 16.0) + seed * 37.3) * 0.7 + blood_noise(uv * vec2(13.0, 40.0) + seed * 11.1) * 0.3;
	float cover = clamp(amount * 1.15, 0.0, 1.0);
	return smoothstep(1.0 - cover, 1.0 - cover + 0.12, n) * clamp(amount * 2.0, 0.0, 1.0);
}

// Color de la sangre en la hoja (lineal): fresca, roja y oscura; seca, casi marrón.
vec3 blood_color(float dry) {
	return mix(vec3(0.16, 0.004, 0.006), vec3(0.05, 0.008, 0.005), dry);
}
