#[compute]
#version 450

// God rays screen-space (Mitchell, GPU Gems 3 "Volumetric Light Scattering as a Post-Process").
// Segundo pase del PlanetAtmosphere: comparte su UBO y se despacha después. Por cada píxel marcha
// hacia la posición en pantalla del sol acumulando la máscara de oclusión del primer pase.
// Solo lee máscara y depth; escribe únicamente su propio píxel del color image.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict image2D color_image;

// 1 = cielo abierto, 0 = ocluido, intermedio = nube. Sampler LINEAR: el bilineal es blur gratis.
layout(set = 0, binding = 1) uniform sampler2D occlusion_mask;
layout(set = 0, binding = 3) uniform sampler2D depth_texture;

// Mismo ParamsBuffer que planet_atmosphere.glsl: el tamaño (42) debe coincidir con
// PARAM_VEC4_COUNT en planet_atmosphere.gd. Aquí se usan P(0)-P(10) y P(27)-P(32).
layout(set = 0, binding = 2, std140) uniform ParamsBuffer {
	vec4 data[42];
} params_buffer;

#include "../liquid/underwater_params.glslinc"
#include "../liquid/underwater_optics.glslinc"

#define P(i) params_buffer.data[i]

const float EPSILON = 0.000001;
const float GOLDEN  = 0.6180339887;

mat4 get_inv_projection() {
	return mat4(P(1), P(2), P(3), P(4));
}

// Dirección de vista en mundo, con la misma reconstrucción que el pase de atmósfera.
vec3 view_ray(vec2 uv) {
	vec4 view = get_inv_projection() * vec4(uv * 2.0 - 1.0, 0.0001, 1.0);
	if (abs(view.w) > EPSILON) view.xyz /= view.w;
	return normalize(P(5).xyz * view.x + P(6).xyz * view.y + P(7).xyz * view.z);
}

// Distancia a la geometría del píxel. Godot es reverse-Z: el cielo llega como 0.
float scene_distance(vec2 uv, ivec2 pixel) {
	float d = texelFetch(depth_texture, pixel, 0).r;
	if (d <= 1e-7) return 1e12;
	vec4 view = get_inv_projection() * vec4(uv * 2.0 - 1.0, d, 1.0);
	if (abs(view.w) > EPSILON) view.xyz /= view.w;
	return length(view.xyz);
}

// Interleaved Gradient Noise (Jimenez 2014): reparte el error del muestreo como un gradiente
// entre píxeles vecinos. Sin él la máscara deja escalones concéntricos alrededor del sol.
float ign_jitter(ivec2 pixel) {
	vec2 p = vec2(pixel);
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

float hash2(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

float vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i),                 hash2(i + vec2(1.0, 0.0)), u.x),
	           mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm2(vec2 p) {
	return vnoise2(p) * 0.65 + vnoise2(p * 2.3 + vec2(11.7, 4.3)) * 0.35;
}

void main() {
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(P(0).xy);
	if (pixel.x >= size.x || pixel.y >= size.y) return;

	if (P(29).w < 0.5) return;

	int debug_mode = int(P(30).x);

	// Sol en pantalla y visibilidad, ambos de CPU (_build_god_ray_sun). La visibilidad ya lleva el
	// gate de sol a la espalda, el falloff angular y el fundido bajo el horizonte.
	vec2  sun_uv  = P(29).xy;
	float sun_vis = P(29).z;
	if (sun_vis <= 0.001 && debug_mode == 0) return;

	vec2 uv = (vec2(pixel) + vec2(0.5)) / vec2(size);
	// Wet pixels already contain refracted underwater shafts in the fused pass.
	if (uw_pixel_wet(uv)) return;

	// Debug 1: máscara cruda + cruz en el sol proyectado (verde = activo, rojo = gateado).
	if (debug_mode == 1) {
		vec3 out_col = vec3(texture(occlusion_mask, uv).r);
		vec2 dpx = abs(vec2(pixel) + vec2(0.5) - sun_uv * vec2(size));
		if ((dpx.y < 1.5 && dpx.x < 14.0) || (dpx.x < 1.5 && dpx.y < 14.0)) {
			out_col = (sun_vis > 0.001) ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
		}
		imageStore(color_image, pixel, vec4(out_col, 1.0));
		return;
	}

	int   steps   = clamp(int(P(28).z), 4, 128);
	float density = clamp(P(28).x, 0.0, 1.0);
	float decay   = clamp(P(28).y, 0.0, 1.0);
	float blur    = max(P(28).w, 0.0);

	float shimmer      = clamp(P(30).y, 0.0, 1.0);
	float shimmer_freq = max(P(30).z, 0.001);
	float shimmer_time = P(30).w;
	float wobble       = P(31).x;
	float max_len      = max(P(31).y, 0.01);
	float scatter_dist = max(P(31).z, 0.1);
	float edge_fade    = max(P(32).y, 0.001);

	// Aire entre la cámara y el píxel: el shaft es luz dispersada POR ese aire, así que sobre el
	// primer plano casi no hay nada y sobre el cielo, todo. Es lo que separa un haz en el espacio
	// de una calca en pantalla.
	float medium = 1.0 - exp(-scene_distance(uv, pixel) / scatter_dist);

	// Ruido del shimmer, anclado al mundo en el plano perpendicular al sol: ni se desliza al girar
	// o escorar la cámara, ni deja de hacer paralaje al desplazarte. La base perpendicular sale de
	// Duff et al. 2017, sin ramas y continua salvo en un polo.
	float wobble_n  = 0.5;
	float shimmer_n = 0.5;
	if (shimmer > 0.001 || abs(wobble) > 0.0001) {
		vec3 sun_dir = normalize(P(10).xyz);
		vec3 rd = view_ray(uv);
		float sgn = (sun_dir.z >= 0.0) ? 1.0 : -1.0;
		float a = -1.0 / (sgn + sun_dir.z);
		float b = sun_dir.x * sun_dir.y * a;
		vec3 t1 = vec3(1.0 + sgn * sun_dir.x * sun_dir.x * a, sgn * b, -sgn * sun_dir.x);
		vec3 t2 = vec3(b, sgn + sun_dir.y * sun_dir.y * a, -sun_dir.y);

		// Punto del haz a scatter_dist por delante de la cámara. P(9) es el centro del planeta
		// relativo a ella, así que negarlo da la cámara relativa al planeta (estable con el
		// origen flotante: ambos se desplazan juntos).
		vec3 sample_p = -P(9).xyz + rd * scatter_dist;
		vec2 perp_coord = vec2(dot(sample_p, t1), dot(sample_p, t2)) * shimmer_freq;
		shimmer_n = fbm2(perp_coord + vec2(shimmer_time, shimmer_time * 0.6));
		wobble_n  = fbm2(perp_coord * 0.4 + vec2(shimmer_time * 0.35 + 31.7, -shimmer_time * 0.2));
	}

	vec2  to_sun   = sun_uv - uv;
	float sun_dist = length(to_sun);
	vec2  dir      = (sun_dist > 1e-6) ? to_sun / sun_dist : vec2(0.0);

	// El wobble gira la DIRECCIÓN, no el origen alrededor del sol: con el sol fuera de encuadre
	// sun_dist se dispara y ese giro desplazaría el origen medio encuadre.
	if (abs(wobble) > 0.0001) {
		float ang = (wobble_n * 2.0 - 1.0) * wobble;
		float cs = cos(ang);
		float sn = sin(ang);
		dir = vec2(dir.x * cs - dir.y * sn, dir.x * sn + dir.y * cs);
	}

	// max_len acota la separación entre muestras: sin tope, a ángulos medios el sol cae a varias
	// pantallas y las mismas muestras se reparten sobre un trayecto enorme (shafts deshechos).
	float march_len = min(sun_dist * density, max_len);
	vec2  delta = dir * (march_len / float(steps));
	vec2  perp = vec2(-dir.y, dir.x);

	float j = ign_jitter(pixel);
	vec2  pos = uv + delta * j;
	float illum = 1.0;
	float accum = 0.0;

	for (int i = 0; i < steps; i++) {
		pos += delta;

		// Secuencia áurea desde el jitter del píxel: desplazamiento distinto por muestra sin
		// volver a hashear y decorrelacionado entre vecinos.
		j = fract(j + GOLDEN);

		// El desparramo crece con la distancia recorrida (penumbra) y sale gratis: son las mismas
		// muestras repartidas en área en vez de en línea.
		vec2 s = pos + perp * ((j - 0.5) * blur * (float(i) / float(steps)));

		// Los taps fuera de encuadre leen el píxel del borde (CLAMP_TO_EDGE); decenas seguidos
		// convertirían uno solo en un shaft infinito de canto duro. Se les baja el peso con la
		// distancia a la que caen: los de al lado siguen contando, los lejanos se apagan.
		vec2 outside = max(max(-s, s - vec2(1.0)), vec2(0.0));
		float w = exp(-length(outside) / edge_fade);

		accum += texture(occlusion_mask, clamp(s, vec2(0.0), vec2(1.0))).r * illum * w;
		illum *= decay;
	}

	// Normalizado por la serie geométrica del decay: accum vale 1 en trayecto despejado sea cual
	// sea el nº de pasos y el decay, así cambiar la calidad no obliga a re-tunear la exposición.
	float norm = (abs(1.0 - decay) < 1e-4)
		? float(steps)
		: (1.0 - pow(decay, float(steps))) / (1.0 - decay);
	accum /= max(norm, 1e-4);

	// Shimmer centrado en 1: reparte brillo entre haces sin subir el brillo medio.
	accum = max(accum * (1.0 + (shimmer_n * 2.0 - 1.0) * shimmer), 0.0);
	accum *= medium;

	// Debug 2: los rayos sobre negro, ya con la atenuación por distancia.
	if (debug_mode == 2) {
		imageStore(color_image, pixel, vec4(vec3(accum), 1.0));
		return;
	}

	// Debug 3: solo la atenuación por distancia (negro = primer plano, blanco = cielo).
	if (debug_mode == 3) {
		imageStore(color_image, pixel, vec4(vec3(medium), 1.0));
		return;
	}

	// Lóbulo de dispersión hacia delante alrededor del sol: la luz de los haces la dispersan los
	// aerosoles, que la mandan casi toda cerca de su dirección. Sin él, accum ≈ 1 en todo el cielo
	// abierto y el pase sumaba un velo uniforme sobre la pantalla entera cuando se miraba hacia el
	// sol —lo que dejaba el cielo de la hora dorada blanco-lavanda y rosa el del ocaso—. El halo
	// en sí ya lo pinta el cielo (Mie); aquí solo quedan los haces, más marcados junto al sol.
	float nu = dot(view_ray(uv), normalize(P(10).xyz));
	const float LOBE_G = 0.75;
	float lobe = pow((1.0 + LOBE_G * LOBE_G - 2.0 * LOBE_G) / (1.0 + LOBE_G * LOBE_G - 2.0 * LOBE_G * nu), 1.5);
	lobe = mix(0.06, 1.0, lobe);

	// Los rayos escalan con sun_intensity: tunear el sol no descuadra la exposición.
	vec3 rays = P(27).rgb * (accum * lobe * P(27).w * sun_vis * P(7).w);

	vec4 scene_color = imageLoad(color_image, pixel);
	imageStore(color_image, pixel, vec4(scene_color.rgb + rays, scene_color.a));
}
