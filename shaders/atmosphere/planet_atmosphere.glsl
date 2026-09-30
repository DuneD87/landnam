#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict image2D color_image;
layout(set = 0, binding = 1) uniform sampler2D depth_texture;

// UBO en vez de SSBO: todos los hilos leen los mismos parámetros, así que van por la
// constant cache. El tamaño (42) debe coincidir con PARAM_VEC4_COUNT en planet_atmosphere.gd
// y con la declaración de god_rays.glsl, que comparte este mismo buffer.
layout(set = 0, binding = 2, std140) uniform ParamsBuffer {
	vec4 data[42];
} params_buffer;

// Rejilla de oclusión radial del WeatherOcclusionField (R = altura del techo de cueva). La niebla
// la usa para no rellenar el aire bajo techo. Si la oclusión está apagada (P(19).w < 0.5) NO se
// muestrea; se bindea aquí una textura cualquiera solo para satisfacer el uniform set.
layout(set = 0, binding = 3) uniform sampler2D occ_height_tex;

// Ruido 3D tileable precalculado (cloud_noise_gen.glsl, generado una vez al inicializar):
// R = Perlin-Worley base (la forma de la nube; cloud_fbm lo apila, ver CLOUD_OCTAVES_*), G = Worley medio
// (reservado), B = Worley fino (reservado desde que la lacunaridad progresiva del FBM aporta
// la erosión), A = Perlin de gran escala (mesoescala de cobertura). Sampler LINEAR + REPEAT.
layout(set = 0, binding = 4) uniform sampler3D cloud_noise_tex;

// Agrupación planetaria: mapa lat-long (u = longitud, v = colatitud) generado en CPU con
// FastNoiseLite (planet_atmosphere.gd). R = envolvente de cobertura (dónde hay cúmulos),
// G = variación de densidad (cómo de gruesos son) — ruidos independientes, así una zona muy
// nublada no es automáticamente una zona de nubes densas. Envuelve el planeta EXACTAMENTE una
// vez → sin repetición de patrón desde el espacio. La misma Image vive en CPU para que el
// weather system pueda consultarla sin readback de GPU. Sampler: REPEAT en u, CLAMP en v.
layout(set = 0, binding = 5) uniform sampler2D cloud_group_tex;

// Máscara de emisión para el segundo pase (god_rays.glsl): 1 = cielo abierto, 0 = ocluido,
// intermedio = nube. La escribe este shader porque es el único que sabe cuánta nube hay: el
// depth buffer no ve el raymarch.
layout(r8, set = 0, binding = 6) uniform restrict writeonly image2D occlusion_mask;

#include "../liquid/underwater_params.glslinc"
// El techo de reflexión total se marcha con la integral del medio (ver el include).
#include "../liquid/underwater_optics.glslinc"

#define P(i) params_buffer.data[i]

// El canal R se horneó con frecuencia base 4 por tile → 1 unidad de noise_pos (la longitud
// de onda del antiguo FBM) equivale a 1/4 de tile, y el patrón se repite cada 4 unidades.
const float CLOUD_NOISE_INV_TILE = 0.25;

const float EPSILON   = 0.000001;
const float MAX_FLOAT = 3.402823466e+38;
const float PI        = 3.14159265359;

// Atmósfera — baja a 6/6 para rendimiento, sube a 16/12 para menos bandas.
const int NUM_IN_SCATTER_POINTS    = 16;
const int NUM_OPTICAL_DEPTH_POINTS = 12;

// Nubes — los pasos de marcha ahora se controlan desde el inspector (PlanetAtmosphere)
// vía P(15): .x = view steps, .y = light steps, .z = shadow steps. Cada lectura va con
// clamp(.., 1, 64) para evitar /0 y bucles runaway. Rango útil: view 8-32, light 3-6,
// shadow 6-12. Más pasos = mejor calidad, más coste.

mat4 get_inv_projection() {
	return mat4(P(1), P(2), P(3), P(4));
}

vec3 view_to_world_dir(vec3 view_dir) {
	vec3 bx = P(5).xyz;
	vec3 by = P(6).xyz;
	vec3 bz = P(7).xyz;
	return bx * view_dir.x + by * view_dir.y + bz * view_dir.z;
}

vec3 reconstruct_view_position(vec2 uv, float depth) {
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
	vec4 view = get_inv_projection() * vec4(ndc, 1.0);
	if (abs(view.w) > EPSILON) {
		view.xyz /= view.w;
	}
	return view.xyz;
}

// Devuelve (dst_to_sphere, dst_through_sphere). Si no impacta: (MAX, 0).
vec2 ray_sphere(vec3 center, float radius, vec3 ro, vec3 rd) {
	vec3 oc = ro - center;
	float b = dot(oc, rd);
	float c = dot(oc, oc) - radius * radius;
	float h = b * b - c;
	if (h < 0.0) return vec2(MAX_FLOAT, 0.0);
	h = sqrt(h);
	float t0 = -b - h;
	float t1 = -b + h;
	if (t1 < 0.0) return vec2(MAX_FLOAT, 0.0);
	float dst_to = max(t0, 0.0);
	return vec2(dst_to, t1 - dst_to);
}


// ===== MODELO DE CIELO =====
// Rayleigh + Mie + capa de ozono, con la transmitancia hacia el sol analítica (función de Chapman)
// en una geometría efectiva. El planeta mide 30 km y su atmósfera 3: con su curvatura real la luz
// rasante apenas cruza aire (el horizonte está a 13 km), el sol casi no se enrojece y, peor, a 10 km
// hacia el sol ya es media tarde. De ahí salía el antiguo "tinte de terminador", que teñía de naranja
// el cielo entero, cénit incluido, y dejaba la hora dorada de color lavanda. Aquí el camino al sol va
// a escala terrestre (P(36).w) sobre la curvatura de un planeta P(37).y veces mayor, y el color sale
// solo: blanco cálido alto, dorado, naranja y rojo al tocar el horizonte; el cénit sigue azul porque
// el aire alto recibe luz menos filtrada, y la capa de ozono lo mantiene azul en el crepúsculo.
//   P(35): .x = dispersión de Mie (1/m), .y = anisotropía g, .z = aerosoles más bajos que el aire
//          (multiplica density_falloff), .w = dispersión múltiple.
//   P(36): .rgb = espesor óptico vertical del ozono, .w = escala del camino al sol.
//   P(37): .x = escala del espesor óptico de los rayos de cielo, .y = curvatura efectiva,
//          .zw = base y techo de la capa de ozono (fracción del grosor de la atmósfera).
struct Sky {
	vec3  sig_r;      // dispersión (= extinción) de Rayleigh, 1/m
	float sig_m;      // dispersión de Mie, 1/m
	float sig_me;     // extinción de Mie, 1/m (albedo 0.9)
	float falloff_m;  // caída de densidad de los aerosoles
	float h_r;        // escala de altura del aire (m)
	float h_m;        // escala de altura de los aerosoles (m)
	float r_eff;      // radio efectivo del planeta para la transmitancia al sol
	float k_sun;      // escala del espesor óptico en el camino al sol
	vec3  ozone;      // espesor óptico vertical de la capa de ozono
	float oz_h1;      // base de la capa de ozono (m sobre la superficie)
	float oz_h2;      // techo
	float g;          // anisotropía de Mie
	float ms;         // dispersión múltiple
	vec3  ms_tint;    // color de la luz de cielo (azulado, lavado)
};

Sky make_sky(vec3 scattering_coeffs, float planet_radius, float atmo_radius, float density_falloff) {
	Sky s;
	float thick = max(atmo_radius - planet_radius, 1.0);
	s.sig_r = scattering_coeffs;
	s.sig_m = P(35).x;
	s.sig_me = P(35).x * 1.11;
	s.falloff_m = density_falloff * max(P(35).z, 1.0);
	s.h_r = thick / max(density_falloff, 0.1);
	s.h_m = thick / max(s.falloff_m, 0.1);
	s.r_eff = planet_radius * max(P(37).y, 1.0);
	s.k_sun = max(P(36).w, 0.0);
	s.ozone = max(P(36).rgb, vec3(0.0));
	s.oz_h1 = thick * P(37).z;
	s.oz_h2 = max(thick * P(37).w, s.oz_h1 + 1.0);
	s.g = clamp(P(35).y, 0.0, 0.99);
	s.ms = max(P(35).w, 0.0);
	float peak = max(scattering_coeffs.r, max(scattering_coeffs.g, scattering_coeffs.b));
	s.ms_tint = mix(vec3(1.0), scattering_coeffs / max(peak, EPSILON), 0.7);
	return s;
}

// Densidad relativa a una altura (m); la misma curva que density_at_point.
float sky_density(float h, float thick, float falloff) {
	float h01 = clamp(h / thick, 0.0, 1.0);
	return exp(-h01 * falloff) * (1.0 - h01);
}

// Función de Chapman (aproximación de Schüler): espesor óptico relativo, en unidades de ρ0·H, desde
// la altura h (en escalas de altura) hasta el infinito con coseno cenital mu. X = radio / H. Bajo el
// horizonte del punto usa la identidad del punto tangente, así que la sombra del planeta sale sola:
// cuando el rayo pasa por debajo del suelo el espesor se dispara y la transmitancia cae a cero.
float chapman(float X, float h, float mu) {
	float x = X + h;
	float c = sqrt(1.5707963 * x);
	if (mu >= 0.0) return exp(-h) * c / ((c - 1.0) * mu + 1.0);
	float xt = x * sqrt(max(1.0 - mu * mu, 0.0));
	float ht = max(xt - X, -30.0);
	float ct = sqrt(1.5707963 * max(xt, 0.001));
	return 2.0 * exp(-ht) * ct - exp(-h) * c / ((c - 1.0) * (-mu) + 1.0);
}

// Recorrido dentro de la bola de radio r + dr de la semirrecta que sale a radio r con coseno mu
// respecto a su vertical. dr en metros (preciso aunque los radios sean de cientos de km).
float ball_path(float r, float mu, float dr) {
	float disc = dr * (2.0 * r + dr) + r * r * mu * mu;   // Rs² - b²
	if (dr >= 0.0) return -r * mu + sqrt(max(disc, 0.0));
	if (mu >= 0.0 || disc <= 0.0) return 0.0;
	return 2.0 * sqrt(disc);
}

// Luz del sol (o de la luna) que llega a una altura h con coseno mu respecto a la vertical local.
vec3 sky_sun_transmittance(Sky s, float h, float mu) {
	h = max(h, 0.0);
	float r = s.r_eff + h;
	// Rayo muy por debajo del suelo efectivo: sombra del planeta, nada que calcular.
	if (mu < 0.0 && r * sqrt(max(1.0 - mu * mu, 0.0)) - s.r_eff < -4.0 * s.h_r) return vec3(0.0);
	float od_r = s.h_r * chapman(s.r_eff / s.h_r, h / s.h_r, mu);
	float od_m = s.h_m * chapman(s.r_eff / s.h_m, h / s.h_m, mu);
	float oz = ball_path(r, mu, s.oz_h2 - h) - ball_path(r, mu, s.oz_h1 - h);
	vec3 tau = (s.sig_r * od_r + vec3(s.sig_me * od_m)) * s.k_sun + s.ozone * (oz / (s.oz_h2 - s.oz_h1));
	return exp(-tau);
}

float phase_rayleigh(float nu) {
	return 0.75 * (1.0 + nu * nu);
}

// Cornette-Shanks, normalizada a media 1 como la de Rayleigh (×4π).
float phase_mie(float nu, float g) {
	float g2 = g * g;
	float k = 1.5 * (1.0 - g2) / (2.0 + g2);
	return k * (1.0 + nu * nu) / pow(max(1.0 + g2 - 2.0 * g * nu, 0.0001), 1.5);
}

// Luz de cielo (dispersión múltiple) disponible con el sol a coseno mu: plena de día y se prolonga
// unos grados tras el ocaso —el cielo de alrededor sigue iluminado—. Con el sol ya bajo el
// horizonte pesa más (hora azul): es la que da el azul profundo del crepúsculo, que la dispersión
// simple de la luz rasante (roja) no produce. El realce no toca el ocaso (mu > 0) para no lavar su
// banda naranja.
const float SKY_MS_TWILIGHT = 1.5;
float sky_ms_brightness(float mu) {
	float twilight = smoothstep(-0.25, -0.08, mu) * (1.0 - smoothstep(-0.06, 0.0, mu));
	return smoothstep(-0.25, 0.02, mu) + SKY_MS_TWILIGHT * twilight;
}

// Luz de la bóveda que baña nubes y niebla con el sol a coseno mu, relativa a la de pleno día.
// Ajustada al ambiente que integra SkyLighting con este mismo modelo: 0,72 con el sol a 7°, 0,29
// al ponerse, 0,06 en el crepúsculo civil y casi nada en el náutico. No vale sky_ms_brightness:
// su realce de la hora azul da color al cielo, pero como luz absoluta dejaba las nubes del
// crepúsculo con el doble de ambiente que a mediodía (manchas blancas pasado el terminador,
// vistas desde órbita).
float sky_ambient_level(float mu) {
	float m = mu - 0.01;
	return m >= 0.0 ? 1.0 - 0.71 * exp(-m / 0.12) : 0.29 * exp(m / 0.042);
}

// Coseno del astro respecto a la vertical "aplanada": a lo largo del rayo la vertical local gira
// inv_flat veces lo que gira de verdad. En un planeta de 30 km, a 10 km hacia el sol la vertical ya
// ha girado 19° y allí sería media tarde: sin aplanar, el cielo del ocaso se iluminaba con luz de
// tarde (blanca) y las nubes de alrededor no se encendían todas a la vez.
float flat_cos(vec3 up, vec3 up_obs, float inv_flat, vec3 dir) {
	return dot(normalize(up_obs + (up - up_obs) * inv_flat), dir);
}


// ===== NUBES VOLUMÉTRICAS =====

float _hash3f(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

// Interleaved Gradient Noise (Jimenez 2014) para el jitter de los raymarches: mismo coste que
// el hash de ruido blanco, pero reparte el error entre píxeles vecinos como un gradiente en vez
// de en grumos → el grano casi desaparece con los mismos pasos. `offset` desplaza el patrón
// para decorrelacionar los distintos marches (nubes / sombra / niebla).
float ign_jitter(ivec2 pixel, float offset) {
	vec2 p = vec2(pixel) + vec2(5.588238, 1.715) * offset;
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

// Asimetría del Mie en los rayos que acaban en el terreno. El cielo lleva el halo de los aerosoles
// (sky.g, ~0,85), pero sobre el relieve ese lóbulo pintaba un resplandor alrededor del sol encima de
// laderas que están a la sombra de la propia montaña: el aire no sabe qué lo tapa, y sombrearlo en
// pantalla dejaba franjas en las siluetas. Casi isótropo conserva la bruma sin el foco; la silueta
// oscura contra el cielo encendido la da el cielo.
const float TERRAIN_MIE_G = 0.2;

float _vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(_hash3f(i),               _hash3f(i + vec3(1,0,0)), u.x),
		    mix(_hash3f(i + vec3(0,1,0)), _hash3f(i + vec3(1,1,0)), u.x), u.y),
		mix(mix(_hash3f(i + vec3(0,0,1)), _hash3f(i + vec3(1,0,1)), u.x),
		    mix(_hash3f(i + vec3(0,1,1)), _hash3f(i + vec3(1,1,1)), u.x), u.y),
		u.z);
}

// FBM normalizado: devuelve ~[0,1] independientemente del nº de octavas. Desde que las
// nubes muestrean la textura 3D precalculada, solo lo usa la niebla a ras de suelo.
float _fbm(vec3 p, int octaves) {
	float v = 0.0, a = 0.5, norm = 0.0;
	for (int i = 0; i < 4; i++, a *= 0.5) {
		if (i >= octaves) break;
		v += a * _vnoise(p);
		norm += a;
		p = p * 2.1 + vec3(1.7, 9.2, 3.4);
	}
	return v / max(norm, EPSILON);
}

float cloud_sun_visibility(
	vec3 p,
	vec3 sun_dir,
	vec3 planet_center,
	float planet_radius,
	float softness
) {
	vec3 oc = p - planet_center;

	// Si proj < 0, el punto está en el lado opuesto al sol.
	float proj = dot(oc, sun_dir);

	// Distancia del punto al eje de la sombra cilíndrica del planeta.
	vec3 closest = oc - sun_dir * proj;
	float axis_dist = length(closest);

	// Dentro del cilindro de sombra: oscuro.
	float visibility = smoothstep(
		planet_radius - softness,
		planet_radius + softness,
		axis_dist
	);

	// En el lado diurno no debe bloquearse.
	if (proj > 0.0) {
		visibility = 1.0;
	}

	return visibility;
}

// edge_soft: anchura del borde del umbral. Los marches de vista/luz pasan la del inspector
// (P(10).w); el de sombra al suelo la pasa ensanchada ×4, porque su jitter por píxel sobre
// una densidad casi binaria produce grano en el terreno (varianza alta entre píxeles
// vecinos) — con el borde ancho el campo es suave, el grano desaparece y la sombra gana
// penumbra blanda.
// Dirección unitaria (desde el centro del planeta) → uv equirectangular del mapa de agrupación.
// DEBE coincidir con la inversa usada en el .gd al generar/consultar la Image (CPU y GPU ven lo mismo).
vec2 latlong_uv(vec3 dir) {
	float u = atan(dir.z, dir.x) * (0.5 / PI) + 0.5;
	float v = acos(clamp(dir.y, -1.0, 1.0)) * (1.0 / PI);
	return vec2(u, v);
}

// Tap al ruido 3D con filtrado quintic (IQ): reajusta la coordenada para que el trilinear
// del hardware siga una curva suave en vez de rampas lineales entre texels — sin esto la
// magnificación fuerte de la textura deja los blobs facetados, con bordes "cortados".
vec4 sample_cloud_noise(vec3 uvw) {
	vec3 size = vec3(textureSize(cloud_noise_tex, 0));
	vec3 tc = uvw * size - 0.5;
	vec3 f = fract(tc);
	tc = floor(tc) + f * f * (3.0 - 2.0 * f) + 0.5;
	return texture(cloud_noise_tex, tc / size);
}

// Rango con signo que el FBM puede desplazar la forma. cloud_fbm normaliza a este valor sea
// cual sea el nº de octavas, así que el umbral de sample_cloud_density no depende de ellas.
const float CLOUD_FBM_AMPLITUDE = 0.875;

// Octavas por tipo de marcha. La de VISTA define la silueta, que es lo único que se ve, así que
// se lleva el detalle. Las de LUZ y SOMBRA solo integran grosor a lo largo de un tramo corto —
// el detalle fino se promedia y no cambia el resultado— y son las que multiplican el coste
// (4 y 8 muestras por paso de vista). Es la misma distinción que hace Heckel con el flag de
// scene(): scene(p, true) en el lightmarch, scene(p, false) en el raymarch.
// 2 octavas bastan en vista: el canal R ya es un FBM de 4 octavas (base 4 → 32 por tile), o sea
// que una sola octava cubre de 500 m a ~62 m de rasgo; la segunda baja a ~31 m y la tercera a
// ~14 m, ya sub-píxel. Sube VIEW a 3 solo si quieres el borde más picado y te sobra fill.
const int CLOUD_OCTAVES_VIEW  = 2;
const int CLOUD_OCTAVES_LIGHT = 1;

// Desviación típica del campo de ruido (P(25).x, cloud_field_sigma en el inspector). `f` es una
// suma de octavas → cuasi-gaussiana, y casi toda su masa vive dentro de ±2σ; los extremos
// ±CLOUD_FBM_AMPLITUDE son rarísimos. Calibra el mapeo cobertura → umbral: con el valor correcto
// cloud_coverage 0.95 cubre ~95% del cielo. El error casi no se nota en coberturas medias y es
// máximo en los extremos, así que se calibra mirando una tormenta.
#define CLOUD_FIELD_SIGMA clamp(P(25).x, 0.05, 1.0)

// Amplitud máxima (en unidades de `coverage`) de la variación de mesoescala. Se alcanza con
// coverage 0.5 y se desvanece hacia los extremos. Súbela para cielos más parcheados; bájala si
// quieres que la tormenta cierre todavía más.
const float CLOUD_MESO_AMOUNT = 0.22;

// FBM CON SIGNO sobre el canal R, con la cadena de lacunaridad progresiva del modelo de Heckel
// (factor 2.02 creciendo +0.21 por octava). Al no doblar exacto, las octavas no se alinean y el
// resultado no se lee como el mismo patrón repetido a varias escalas. El signo es lo esencial:
// el ruido no MULTIPLICA la forma, la DESPLAZA — la infla donde es positivo y la erosiona donde
// es negativo. Devuelve ~[-CLOUD_FBM_AMPLITUDE, +CLOUD_FBM_AMPLITUDE].
// La octava base ya NO va a `noise_scale`, sino a noise_scale × shape_ratio (P(25).w). Antes un
// solo número fijaba a la vez el tamaño de la masa y la finura del borde: bajar noise_scale daba
// nubes grandes pero borrosas, y subirlo, nubes finas pero todas diminutas. Separando las dos
// bandas, `noise_scale` se queda con el detalle y `shape_ratio` manda en el tamaño.
// No queda hueco en el espectro entre ambas: cada tap al canal R es ya un FBM de 4 octavas que
// abarca ×8 en frecuencia, así que forma (r·f … 8r·f) y detalle (f … 8f) se solapan mientras
// shape_ratio ≥ 1/8. Por debajo, sube CLOUD_OCTAVES_VIEW a 3 para rellenar la banda media.
// `size` [0,1] reparte AMPLITUD entre la banda de forma y la de detalle: 1 = manda la forma
// (masas grandes y coherentes), 0 = manda el detalle (borregos pequeños y sueltos). Es un
// reparto de amplitud, no de frecuencia — escalar el dominio por región cizallaría el ruido,
// porque el gradiente del mapa de tamaño se suma a la frecuencia local y llega a superarla.
// `detail` [0,1] atenúa las octavas finas cuando su rasgo cae por debajo de dos muestras por
// píxel: ahí ya no aportan forma, solo aliasing.
float cloud_fbm(vec3 q, int octaves, float detail, float size) {
	float bias = (clamp(size, 0.0, 1.0) - 0.5) * 2.0 * clamp(P(26).x, 0.0, 1.0);
	float w_shape  = 1.0 + bias;
	float w_detail = 1.0 - bias;
	float shape_ratio = clamp(P(25).w, 0.05, 0.95);

	// La octava de forma va con el filtrado quintic: es la más magnificada (rasgos grandes sacados
	// de una textura de 128³) y sin el remapeo los blobs salen facetados. Las finas usan el
	// trilinear crudo — a ×2 y más la magnificación ya no lo necesita y nos ahorramos el remapeo
	// de coordenada, que es ALU justo delante del tap.
	float a  = 0.5 * w_shape;
	float f  = a * (sample_cloud_noise(q * shape_ratio).r * 2.0 - 1.0);
	float sq = a * a;
	// Amplitudes de referencia (reparto neutro): la normalización final las usa para que el campo
	// conserve la MISMA sigma pase lo que pase con el reparto. Si no, las regiones de nubes grandes
	// saldrían con más varianza, cubrirían más cielo que el prometido por `coverage` y
	// cov_to_threshold —calibrado sobre CLOUD_FIELD_SIGMA— dejaría de valer.
	float ref_norm = 0.5;
	float ref_sq   = 0.25;

	float scale = 0.25 * clamp(detail, 0.0, 1.0);
	float factor = 2.02;
	vec3  p = q;   // primera octava de detalle: exactamente la frecuencia del inspector
	for (int i = 1; i < octaves; i++) {
		a  = scale * w_detail;
		f  += a * (texture(cloud_noise_tex, p).r * 2.0 - 1.0);
		sq += a * a;
		ref_norm += scale;
		ref_sq   += scale * scale;
		factor += 0.21;
		p *= factor;
		scale *= 0.5;
	}
	// Normalizado a CLOUD_FBM_AMPLITUDE: si no, la marcha de luz (1 octava) vería sistemáticamente
	// MENOS nube que la de vista (2 octavas) y las nubes saldrían sub-sombreadas — el umbral es el
	// mismo para todas y tiene que ver el mismo rango. El factor sqrt(ref_sq)/sqrt(sq) reproduce
	// exactamente la escala anterior con reparto neutro y solo corrige la deriva que introduce el
	// reparto por tamaño.
	return f * (CLOUD_FBM_AMPLITUDE * sqrt(ref_sq) / (ref_norm * max(sqrt(sq), 0.0001)));
}

// Cobertura local = agrupación planetaria (mapa lat-long, P(15).w = strength) × mesoescala
// (Perlin de gran escala, canal A del ruido 3D, a 1/4 de frecuencia). Se evalúa EN cada paso
// de los marches de vista y sombra —así nube visible y sombra proyectada leen lo mismo en el
// mismo sitio del mundo— y ANTES del tap de densidad: si la celda está despejada, el llamador
// se salta la muestra entera (cielo limpio = solo este coste). La marcha de luz hereda la
// cobertura del punto que ilumina: su tramo es corto y estas escalas no cambian en él. La
// mesoescala usa solo la posición horizontal advectada (sin offset vertical ni cizalla): es
// variación regional, no de forma.
// Devuelve .x = cobertura [0, 0.98], .y = multiplicador de densidad del cúmulo y .z = tamaño de
// nube [0,1] (ver cloud_fbm). Los tres salen de taps que ya se hacían — densidad del canal G del
// mapa de agrupación, tamaño del canal R del tap de mesoescala — así que ninguno cuesta un texel
// más. Sin ellos todos los cúmulos del planeta tenían el mismo grosor y el mismo tamaño: la
// agrupación solo decidía cuánto hueco había entre ellos, no qué aspecto tenía cada uno.
vec3 local_coverage(
	vec3 p, vec3 planet_center, float coverage,
	float cloud_min_r, float cloud_max_r, float noise_scale
) {
	float strength = clamp(P(15).w, 0.0, 1.0);
	float density_mul = 1.0;
	if (strength > 0.001) {
		vec2 grp = texture(cloud_group_tex, latlong_uv(normalize(p - planet_center))).rg;
		coverage *= mix(1.0, grp.r, strength);
		// El canal G es ruido independiente centrado en 0.5, así que el multiplicador queda
		// centrado en 1: subir la variación reparte grosores sin cambiar el aspecto MEDIO del
		// cielo, y cloud_density sigue significando lo mismo.
		float variation = clamp(P(25).z, 0.0, 1.0);
		density_mul = mix(1.0, 1.0 + (grp.g - 0.5) * 2.0 * variation, strength);
	}
	float reference_r = max((cloud_min_r + cloud_max_r) * 0.5, 1.0);
	vec3 noise_pos = ((p - planet_center) / reference_r) * max(noise_scale, 0.001)
	               + P(14).xyz * P(14).w;
	// Un solo tap de gran escala da las DOS variaciones regionales: .a (Perlin base 2) es la
	// mesoescala de cobertura y .r (Perlin-Worley base 4) el mapa de tamaño de nube. Son ruidos
	// distintos de la misma textura, así que "más nublado" y "nubes más grandes" no van atados.
	vec4 low = sample_cloud_noise(noise_pos * (CLOUD_NOISE_INV_TILE * 0.25));
	float meso = low.a;
	float size = low.r;

	// La mesoescala perturba la cobertura de forma ADITIVA, con la amplitud escalada por el
	// margen que queda hasta el extremo más cercano. Multiplicando plano (mix(0.55, 1.35, meso))
	// la cobertura caía al 0.55× en las celdas de meso bajo pasara lo que pasara, así que ni con
	// coverage 0.95 cerraba el manto: ahí quedaba un 52% de cielo cubierto y se veían claros en
	// plena tormenta. Con el margen, `coverage` conserva el contrato que promete cov_to_threshold
	// en los extremos (≈1 = manto cerrado, ≈0 = cielo limpio) y la mesoescala sigue mandando en
	// el rango medio, que es donde debe notarse.
	float meso_room = 2.0 * min(coverage, 1.0 - coverage);
	coverage += (meso - 0.5) * (2.0 * CLOUD_MESO_AMOUNT) * meso_room;
	return vec3(clamp(coverage, 0.0, 0.98), density_mul, size);
}

// Densidad de nube como CAMPO CON SIGNO (raymarching volumétrico estilo Heckel):
// campo = -sdf(forma) + fbm - umbral. La forma es el sdf de la cáscara de nubes normalizado
// y el FBM con signo desplaza su frontera, así que el CRUCE POR CERO del campo es la silueta.
// De ahí salen masas abombadas con protuberancias, en vez de la lámina recortada que daba el
// umbral anterior: aquel hacía smoothstep(1-coverage, ruido) × un height_grad de altura fija,
// es decir cortaba una losa a una altitud constante, y por eso la capa se leía como un estrato.
// `coverage` entra ahora como SESGO del umbral, no como corte del ruido.
// Cobertura [0,1] → umbral del campo, calibrado sobre la distribución REAL del ruido en vez de
// barrer ±CLOUD_FBM_AMPLITUDE linealmente. Con el barrido lineal la fracción de cielo cubierta
// se desplomaba por debajo de coverage ~0.35, porque la mayor parte del recorrido se gastaba en
// las colas de la gaussiana, donde apenas hay muestras. Eso hacía que cloud_group_strength no
// se notara en medio recorrido, que la envolvente de agrupación se comportase como binaria por
// suave que fuese su transición, y que en la banda intermedia lo poco que asomaba fuesen motas
// diminutas. La curva es un logit escalado (≈ probit, el inverso de la gaussiana acumulada), de
// modo que el área cubierta sigue a `coverage` casi linealmente. El clamp lleva los extremos a
// ±AMPLITUDE para garantizar cielo limpio en 0 y manto total en 1.
// Se evalúa UNA vez por punto en el llamador, no por muestra: la marcha de luz hereda el umbral
// del punto que ilumina, igual que ya heredaba la cobertura.
float cov_to_threshold(float coverage) {
	float c = clamp(coverage, 0.001, 0.999);
	float probit = log(c / (1.0 - c)) * (CLOUD_FIELD_SIGMA / 1.7);   // logit ≈ 1.7 × probit
	return 1.0 - clamp(probit, -CLOUD_FBM_AMPLITUDE, CLOUD_FBM_AMPLITUDE);
}

float sample_cloud_density(
	vec3 p, vec3 planet_center,
	float cloud_min_r, float cloud_max_r,
	float threshold, float density_scale, float noise_scale,
	float edge_soft, int octaves, float detail, float size
) {
	vec3 local = p - planet_center;
	float dist = length(local);

	if (dist < cloud_min_r || dist > cloud_max_r) {
		return 0.0;
	}

	vec3 dir = local / max(dist, EPSILON);

	float thickness = max(cloud_max_r - cloud_min_r, 0.001);
	float h = clamp((dist - cloud_min_r) / thickness, 0.0, 1.0);

	// -sdf de la cáscara, normalizado a [0,1]: 1 en la capa media, 0 en base y cima. Sustituye
	// al height_grad — ya no atenúa una densidad calculada aparte, ES el término de forma que
	// el FBM desplaza, y por eso la nube se abomba hacia arriba y hacia abajo por sí sola.
	float shape = 1.0 - abs(h - 0.5) * 2.0;

	// noise_scale ahora actúa como frecuencia alrededor del planeta.
	// Valores típicos: 8 - 40.
	float reference_r = max((cloud_min_r + cloud_max_r) * 0.5, 1.0);
	float freq = max(noise_scale, 0.001);

	// Ruido anclado al planeta, no a la cámara.
	vec3 noise_pos = (local / reference_r) * freq;

	// Variación vertical radial. Valor pequeño (0.5–1.0) evita deformación al mover la cámara.
	noise_pos += dir * (h * 0.8);

	// Movimiento de viento con cizalla vertical: P(14).xyz = dirección, P(14).w = tiempo ×
	// velocidad. La cima de la capa avanza más deprisa que la base (como el viento real, que
	// crece con la altura) → las masas se estiran en vetas a lo largo del viento en vez de
	// viajar como bloques rígidos. Visible sobre todo desde el espacio.
	noise_pos += P(14).xyz * (P(14).w * mix(0.85, 1.3, h));

	// Un tap por octava. Todos los marches (vista, luz, sombra) llaman aquí sobre el MISMO campo,
	// así que las sombras siguen coincidiendo con lo visible; solo cambia cuánto detalle pide cada
	// uno (ver CLOUD_OCTAVES_*). La mesoescala NO se muestrea aquí: viene ya aplicada en
	// `coverage` (local_coverage).
	float f = cloud_fbm(noise_pos * CLOUD_NOISE_INV_TILE, octaves, detail, size);

	// El umbral llega ya calculado por el llamador (cov_to_threshold), con la agrupación
	// planetaria y la mesoescala aplicadas en la cobertura de la que sale.
	float field = shape + f - threshold;

	// La densidad ES el valor del campo, SIN saturar: crece de 0 en la frontera a ~1 en el núcleo.
	// Esa gradación es la que produce el sombreado interno, porque hace que el l_od de la marcha
	// de luz varíe de una muestra a otra. Saturarla a 1 con un smoothstep la aplana: densidad
	// binaria → beer y powder constantes → toda la nube a un único brillo, blanca y plana.
	// edge_soft = anchura del empalme alrededor del cruce por cero (soft-plus cuadrático: 0 por
	// debajo de -edge_soft, exactamente `field` por encima de +edge_soft, C1 en el medio). La
	// marcha de sombra lo pasa ensanchado ×4 para ganar penumbra.
	float k = max(edge_soft, 0.001);
	float knee = max(field + k, 0.0);
	float density = (field >= k) ? field : knee * knee * (0.25 / k);

	return density * density_scale;
}

float hg_phase(float cos_theta, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (4.0 * PI * pow(max(1.0 + g2 - 2.0 * g * cos_theta, 0.001), 1.5));
}

float cloud_light_od(
	vec3 p, vec3 sun_dir,
	vec3 planet_center, float cloud_min_r, float cloud_max_r,
	float threshold, float density_scale, float noise_scale, float size
) {
	vec2 hit = ray_sphere(planet_center, cloud_max_r, p, sun_dir);
	if (hit.y <= 0.0) return 0.0;
	int light_steps = clamp(int(P(15).y), 1, 64);
	float step_sz = hit.y / float(light_steps);
	float od = 0.0;
	float edge_soft = clamp(P(10).w, 0.01, 0.5);
	vec3 lp = p + sun_dir * (step_sz * 0.5);
	for (int i = 0; i < light_steps; i++) {
		od += sample_cloud_density(lp, planet_center, cloud_min_r, cloud_max_r,
		                           threshold, density_scale, noise_scale, edge_soft,
		                           CLOUD_OCTAVES_LIGHT, 0.0, size) * step_sz;
		lp += sun_dir * step_sz;
	}
	return od;
}

// Sombra de nube proyectada sobre la superficie: transmitancia de la luz solar a
// través de la capa de nube, medida desde un punto del terreno hacia el sol.
// Solo marcha el segmento del rayo que cruza la cáscara [cloud_min_r, cloud_max_r].
float cloud_shadow_transmittance(
	vec3 p, vec3 sun_dir,
	vec3 planet_center, float cloud_min_r, float cloud_max_r,
	float coverage, float density_scale, float noise_scale, float absorption,
	float jitter
) {
	vec2 outer = ray_sphere(planet_center, cloud_max_r, p, sun_dir);
	if (outer.y <= 0.0) return 1.0;                  // el rayo al sol no alcanza la capa

	// Punto bajo la base de las nubes: inner.y = salida de la esfera interior = base
	// de la cáscara. Punto ya dentro de la cáscara: sin impacto interior, arranca en p.
	vec2 inner = ray_sphere(planet_center, cloud_min_r, p, sun_dir);
	float t_start = inner.y > 0.0 ? inner.y : 0.0;
	float seg = outer.y - t_start;
	if (seg <= 0.001) return 1.0;

	// Borde ensanchado ×4 SOLO para la sombra: con el umbral casi binario de la nube visible,
	// el jitter por píxel de esta marcha producía grano en el terreno (píxeles vecinos
	// atravesaban cantidades de nube muy distintas). El campo suavizado mata esa varianza
	// y de paso da penumbra blanda a la sombra. La nube visible no cambia.
	float edge_soft = min(clamp(P(10).w, 0.01, 0.5) * 4.0, 0.5);
	int shadow_steps = clamp(int(P(15).z), 1, 64);
	float step_sz = seg / float(shadow_steps);
	float od = 0.0;
	vec3 lp = p + sun_dir * (t_start + step_sz * (0.5 + jitter));
	for (int i = 0; i < shadow_steps; i++) {
		// Cobertura local en el propio paso: la misma que ve la nube visible en ese punto
		// del cielo. En celda despejada no hay nube que proyecte → ni tap de densidad.
		vec3 cov = local_coverage(lp, planet_center, coverage,
		                          cloud_min_r, cloud_max_r, noise_scale);
		if (cov.x >= 0.02) {
			od += sample_cloud_density(lp, planet_center, cloud_min_r, cloud_max_r,
			                           cov_to_threshold(cov.x), density_scale * cov.y, noise_scale,
			                           edge_soft, CLOUD_OCTAVES_LIGHT, 0.0, cov.z) * step_sz;
		}
		lp += sun_dir * step_sz;
	}
	return exp(-od * absorption);
}

void march_clouds(
	vec3 ro, vec3 rd, float max_dist,
	vec3 planet_center, float cloud_min_r, float cloud_max_r,
	float density_scale, float coverage,
	float absorption, float g, float noise_scale,
	vec3 sun_dir, float sun_intensity, float planet_radius,
	vec3 scattering_coeffs,
	float jitter, float pixel_angle,
	Sky sky, vec3 up_obs, float inv_flat,
	out vec3 out_color, out float out_trans, out float out_dist
) {
	out_color = vec3(0.0);
	out_trans = 1.0;
	out_dist  = 0.0;

	// Distancia media de la nube, ponderada por lo que aporta cada muestra al color final. La
	// usa el llamador para darle a la nube la misma perspectiva aérea que al resto de la escena.
	float dist_acc   = 0.0;
	float weight_acc = 0.0;

	vec2 outer = ray_sphere(planet_center, cloud_max_r, ro, rd);
	if (outer.y <= 0.0) return;

	float t0 = outer.x;
	float t1 = outer.x + outer.y;

	// Recortar por la esfera interior (base de la capa de nubes).
	// - Cámara DENTRO de la esfera interior (en superficie): inner.x == 0, marchar desde la salida.
	// - Cámara FUERA de la esfera interior: cortar t1 antes de entrar en ella.
	vec2 inner = ray_sphere(planet_center, cloud_min_r, ro, rd);

	if (inner.y > 0.0) {
		float ro_r = length(ro - planet_center);

		// Cámara debajo de la base de las nubes: empezar al salir de la esfera interior.
		if (ro_r < cloud_min_r) {
			t0 = max(t0, inner.x + inner.y);
		}
		// Cámara fuera de la esfera interior: cortar antes de entrar en ella.
		else {
			t1 = min(t1, inner.x);
		}
	}

	t0 = max(t0, 0.0);
	t1 = min(t1, max_dist);
	if (t1 <= t0 + 0.001) return;

	int cloud_steps = clamp(int(P(15).x), 1, 64);
	float step_size = (t1 - t0) / float(cloud_steps);
	float big_step  = step_size * 2.0;   // pasos grandes en aire limpio
	float cos_theta = dot(rd, sun_dir);

	// Fase de doble lóbulo: el HG hacia delante (g del inspector) da el silver lining mirando
	// al sol; el lóbulo trasero fijo añade la retro-dispersión que hace brillar las nubes con
	// el sol a la espalda (con un solo lóbulo quedaban planas y muertas en esa dirección).
	float phase = mix(hg_phase(cos_theta, g), hg_phase(cos_theta, -0.3), 0.3);

	// Luna: donde el sol ya no llega (cara nocturna) la marcha de luz va hacia ella, así que de
	// noche las nubes quedan plateadas con el mismo coste que de día. P(33)/P(34) como en el cielo.
	vec3 moon_dir = normalize(P(33).xyz);
	float moon_intensity = P(33).w;
	float cos_theta_moon = dot(rd, moon_dir);
	float moon_phase = mix(hg_phase(cos_theta_moon, g), hg_phase(cos_theta_moon, -0.3), 0.3);

	// Tinte del ambiente derivado de los coeficientes de Rayleigh: a las zonas en sombra de la
	// nube las ilumina la bóveda del cielo, así que heredan su azul — y siguen el color de la
	// atmósfera del planeta sin parámetro nuevo. Mezcla con blanco para no saturar.
	float coeff_max = max(scattering_coeffs.r, max(scattering_coeffs.g, scattering_coeffs.b));
	vec3 sky_ambient = mix(vec3(1.0), scattering_coeffs / max(coeff_max, EPSILON), 0.55);
	float thickness = max(cloud_max_r - cloud_min_r, 0.001);

	float edge_soft = clamp(P(10).w, 0.01, 0.5);   // anchura de borde del inspector

	// LOD del ruido. Rasgo más fino que aporta la octava de detalle: el rasgo base del canal R
	// mide planet_radius/noise_scale, la octava 1 lo divide entre 2.02 y R lleva 4 octavas
	// internas (hasta ×8) → /16 en total. Por debajo de dos muestras por píxel esa octava ya no
	// aporta forma, solo aliasing (el speckle desde órbita), así que se desvanece — y cuando su
	// aportación es despreciable nos ahorramos también su tap. Se evalúa UNA vez por rayo, con
	// t0 (la entrada en la capa): la variación a lo largo del segmento no justifica el coste
	// por paso, y usar t0 peca de conservador, que es el lado bueno del error.
	float fine_feature = (planet_radius / max(noise_scale, 0.001)) * (1.0 / 16.0);
	float detail = 1.0 - smoothstep(fine_feature * 0.5, fine_feature * 2.0, t0 * pixel_angle);
	int view_octaves = (detail > 0.02) ? CLOUD_OCTAVES_VIEW : 1;

	// Empty-space skipping: con la textura 3D la muestra completa cuesta un solo tap, así
	// que hace ella misma de sonda. En aire limpio avanzamos con pasos grandes; dentro de
	// la nube, finos. El presupuesto extra cubre el caso de rayos mayormente vacíos.
	int MAX_MARCH_ITERS = cloud_steps + cloud_steps / 2;
	float t = t0 + step_size * jitter;

	for (int i = 0; i < MAX_MARCH_ITERS && t < t1; i++) {
		vec3 p = ro + rd * t;

		// Cobertura local en el propio punto (no en el punto medio del rayo: en vistas
		// rasantes caía en otra celda de agrupación y la nube visible no coincidía con la
		// sombra que proyectaba). Con la celda despejada nos saltamos el tap de densidad
		// entero: el cielo limpio solo paga la cobertura.
		vec3 cov = local_coverage(p, planet_center, coverage,
		                          cloud_min_r, cloud_max_r, noise_scale);
		if (cov.x < 0.02) {
			t += big_step;
			continue;
		}
		// Un solo logit por paso de vista: la marcha de luz hereda este mismo umbral, y con él la
		// densidad y el tamaño del cúmulo — si no, un cúmulo delgado se auto-sombrearía como uno de
		// tormenta y la luz atravesaría un campo con otra forma que el visible.
		float thr = cov_to_threshold(cov.x);
		float dens = density_scale * cov.y;
		float d = sample_cloud_density(p, planet_center, cloud_min_r, cloud_max_r,
		                               thr, dens, noise_scale, edge_soft,
		                               view_octaves, detail, cov.z);
		if (d <= 0.0001) {
			t += big_step;
			continue;
		}

		{
			// Qué luz ilumina esta muestra: el sol, con el color que le deja el aire que cruza hasta
			// ella (sky_sun_transmittance: el ocaso las enciende de naranja y rosa, y las altas siguen
			// al sol un rato después de que el suelo quede en sombra), y en la cara nocturna la luna.
			// Una sola marcha de luz por muestra, y ninguna donde solo queda la luz del cielo.
			vec3 up_c = normalize(p - planet_center);
			float h_c = length(p - planet_center) - planet_radius;
			float mu_sun = flat_cos(up_c, up_obs, inv_flat, sun_dir);
			vec3 sun_col = sky_sun_transmittance(sky, h_c, mu_sun);
			float sun_peak = max(sun_col.r, max(sun_col.g, sun_col.b));
			float sky_light = sky_ambient_level(mu_sun);
			vec3 moon_col = vec3(0.0);
			float moon_vis = 0.0;
			if (moon_intensity > 0.0 && sun_peak <= 0.002) {
				moon_col = sky_sun_transmittance(sky, h_c, flat_cos(up_c, up_obs, inv_flat, moon_dir));
				moon_vis = max(moon_col.r, max(moon_col.g, moon_col.b));
			}
			bool by_moon = moon_vis > 0.001;
			bool direct = sun_peak > 0.002 || by_moon;
			vec3 light_dir = by_moon ? moon_dir : sun_dir;

			vec3 lighting = vec3(0.0);
			if (direct || sky_light > 0.001) {
				float shadow_softness = max(cloud_max_r - cloud_min_r, planet_radius * 0.005);
				float shadow = cloud_sun_visibility(p, light_dir, planet_center, planet_radius, shadow_softness);

				float direct_light = 0.0;
				if (direct) {
					float l_od = cloud_light_od(p, light_dir, planet_center, cloud_min_r, cloud_max_r,
												thr, dens, noise_scale, cov.z);
					// Multi-scattering aproximado (Schneider): el Beer puro apagaba cualquier nube
					// gruesa en gris plomo uniforme. La segunda exponencial —absorción ×0.25, techo
					// 0.7— simula la luz que rebota varias veces dentro de la nube e ilumina el
					// interior; el max conserva intacto el pico de la directa en los bordes finos.
					float beer   = max(exp(-l_od * absorption), 0.7 * exp(-l_od * absorption * 0.25));
					// El powder aproxima el oscurecimiento cerca de la superficie iluminada, así que su
					// escala de profundidad es una propiedad de la NUBE, no del integrador: va con una
					// longitud de referencia fija (proporcional al grosor) y NO con step_size, para que
					// la radiancia no cambie con la dirección de vista ni con la posición de la cámara.
					float powder = 1.0 - exp(-d * (thickness * 0.05) * absorption * 2.0);
					direct_light = beer * powder * 2.0 * (by_moon ? moon_phase : phase) * shadow;
				}

				// Ambiente celeste con gradiente de altura: la cima ve toda la bóveda (más luz), la base
				// casi nada; así el sol rasante del amanecer SÍ puede encender las bases. Es la luz del
				// cielo, que dura un poco más que la directa tras el ocaso.
				float h_amb = clamp((length(p - planet_center) - cloud_min_r) / thickness, 0.0, 1.0);
				vec3 ambient_light = sky_ambient * (mix(0.05, 0.16, h_amb) * shadow);

				// La luz del cielo (el aire de encima, aún con sol en el crepúsculo) va con o sin luna.
				// Una nube de tormenta —gruesa, con la directa apagada por su grosor/albedo— se queda
				// gris en vez de teñirse: el color del ocaso solo va en la directa.
				lighting = ambient_light * (sky_light * sun_intensity);
				if (by_moon) {
					// Luz de luna: fría, y rojiza también ella cuando está baja.
					lighting += (moon_col * direct_light + ambient_light * moon_vis)
						* (sun_intensity * moon_intensity) * P(34).rgb;
				} else {
					lighting += sun_col * (direct_light * sun_intensity);
				}
			}

			// Albedo de la nube (P(23).z): su reflectividad. 1 = brillo pleno (nube blanca); valores
			// bajos la oscurecen hacia un gris de tormenta. Multiplica TODA la radiancia (directa +
			// ambiente), así baja del suelo ambiental que la opacidad por sí sola no podía rebajar.
			// Independiente de cloud_absorption (opacidad) y de cloud_shadow_strength (sombra al suelo).
			lighting *= P(23).z;

			// Destello de rayo (P(9).w, lightning_flash): emisión breve DENTRO de la nube. Va después
			// del albedo (una nube de tormenta oscura igual fogonea) y del gradiente día/noche (el rayo
			// ilumina la nube también de noche, cuando más luce). Se acumula como el resto de la
			// radiancia → las nubes densas destellan más. Tinte azul-blanco; 12.0 = fuerza (a ojo).
			lighting += vec3(0.7, 0.8, 1.0) * (P(9).w * 12.0);

			float s_trans = exp(-d * step_size * absorption);

			float w = out_trans * (1.0 - s_trans);
			out_color  += w * lighting;
			dist_acc   += w * t;
			weight_acc += w;
			out_trans  *= s_trans;

			if (out_trans < 0.005) { out_trans = 0.0; break; }
		}
		t += step_size;
	}

	out_dist = (weight_acc > 0.0) ? (dist_acc / weight_acc) : 0.0;
}


// ===== NIEBLA A RAS DE SUELO =====
// Capa volumétrica baja e independiente de las nubes. La densidad la modula un ruido de
// gran escala advectado por el viento (P(18).y), de modo que los bancos viajan
// horizontalmente y "se ven venir de lejos". Es densa abajo y se desvanece hacia arriba,
// así que se origina pegada al suelo en vez de bajar del cielo.

// Setup de la oclusión de cueva, invariante a lo largo del rayo: se construye UNA vez por
// píxel en march_fog en lugar de desempaquetar P() y llamar a textureSize en cada muestra.
struct FogOcclusion {
	bool  enabled;
	vec3  center;
	vec3  x_axis;
	vec3  z_axis;
	vec3  up;
	float inv_half;   // 1 / semiancho de la rejilla
	float span;
	float below;
	float margin;
	float inv_soft;   // 1 / metros de difuminado del borde
	float step_uv;    // separación de las 9 muestras del PCF, en uv
};

FogOcclusion make_fog_occlusion() {
	FogOcclusion o;
	o.enabled = P(19).w > 0.5;
	o.center  = P(19).xyz;
	o.x_axis  = P(20).xyz;
	o.z_axis  = P(21).xyz;
	o.up      = P(22).xyz;
	o.span    = P(21).w;
	o.below   = P(22).w;
	o.margin  = P(23).x;
	float occ_half = max(P(20).w, EPSILON);
	float occ_soft = max(P(23).y, 0.5);   // metros de difuminado del borde (horizontal + vertical)
	o.inv_half = 1.0 / occ_half;
	o.inv_soft = 1.0 / occ_soft;
	// Separación de las 9 muestras: occ_soft metros, con un téxel como mínimo. La rejilla
	// va de -1..1 en u → uv = u*0.5+0.5, así que 1 uv equivale a 2*occ_half metros.
	vec2 res = vec2(textureSize(occ_height_tex, 0));
	o.step_uv = max(occ_soft * 0.5 * o.inv_half, 1.0 / max(res.x, res.y));
	return o;
}

float sample_fog_density(
	vec3 p, vec3 planet_center,
	float fog_min_r, float fog_max_r,
	float coverage, float noise_scale, vec3 wind_dir, float wind_offset,
	FogOcclusion occ
) {
	vec3 local = p - planet_center;
	float dist = length(local);
	if (dist < fog_min_r || dist > fog_max_r) {
		return 0.0;
	}

	// Oclusión de cueva: si el punto cae dentro de la rejilla del WeatherOcclusionField y queda
	// por debajo del techo (roca) detectado sobre el jugador, aquí no hay niebla (estás en cueva).
	// PCF 3x3: promediamos el aporte de oclusión de 9 muestras separadas occ_soft metros, así el
	// borde (boca de cueva) se difumina en HORIZONTAL y VERTICAL en vez de salir en columnas.
	float occ_mult = 1.0;   // 1 = niebla normal; 0 = bajo techo (cueva)
	if (occ.enabled) {
		vec3 orel = p - occ.center;
		float ou = dot(orel, occ.x_axis) * occ.inv_half;
		float ow = dot(orel, occ.z_axis) * occ.inv_half;
		if (abs(ou) <= 1.0 && abs(ow) <= 1.0) {   // fuera de la rejilla = sin dato = niebla normal
			vec2 ouv = vec2(ou, ow) * 0.5 + 0.5;
			float point_h = dot(orel, occ.up);
			float occ_accum = 0.0;
			for (int oy = -1; oy <= 1; oy++) {
				for (int ox = -1; ox <= 1; ox++) {
					vec2 suv = ouv + vec2(float(ox), float(oy)) * occ.step_uv;
					float ceil_h = texture(occ_height_tex, suv).r * occ.span - occ.below;
					// Aporte [0,1]: 1 bien bajo su techo (dentro), 0 al ras o por encima (fuera). Las
					// celdas "sin techo" decodifican muy abajo → su aporte es 0 (no ocluyen).
					occ_accum += clamp(((ceil_h + occ.margin) - point_h) * occ.inv_soft, 0.0, 1.0);
				}
			}
			occ_mult = 1.0 - occ_accum / 9.0;   // promedio 3x3 → borde difuso en todas direcciones
			if (occ_mult <= 0.001) {
				return 0.0;   // totalmente bajo techo: nos saltamos AMBOS FBM
			}
		}
	}

	float thickness = max(fog_max_r - fog_min_r, 0.001);
	float h = clamp((dist - fog_min_r) / thickness, 0.0, 1.0);

	// Densa en el suelo, se desvanece hacia el techo (curva suave para un borde superior difuso).
	float height_grad = 1.0 - smoothstep(0.0, 1.0, h);
	height_grad *= height_grad;
	if (height_grad <= 0.0001) {
		return 0.0;   // en el techo de la niebla no hay nada: evitamos AMBOS FBM.
	}

	// Agrupación: la niebla del evento solo cuaja BAJO la celda de nubes, leyendo el MISMO mapa
	// que usan la cobertura de nubes y el in-scatter. Sin esto la bruma de tormenta era un velo
	// gris global que te acompañaba también por los claros. P(25).y = peso por evento (fog_group):
	// 0 = manto global clásico (el evento 'fog' lo quiere así), 1 = confinada a la celda.
	// El tap de textura se paga aquí, tras los early-out baratos y antes de los dos FBM.
	float fog_group = clamp(P(25).y, 0.0, 1.0) * clamp(P(15).w, 0.0, 1.0);
	if (fog_group > 0.001) {
		coverage *= mix(1.0, texture(cloud_group_tex, latlong_uv(normalize(local))).r, fog_group);
		if (coverage <= 0.02) {
			return 0.0;
		}
	}

	// Banco de gran escala anclado al planeta y desplazado por el viento.
	float reference_r = max(fog_min_r, 1.0);
	vec3 noise_pos = (local / reference_r) * max(noise_scale, 0.001);
	noise_pos += wind_dir * wind_offset;

	float bank = _fbm(noise_pos, 3);
	// coverage alto → umbral bajo → más manto; coverage bajo → parches sueltos.
	float mass = smoothstep(1.0 - coverage, 1.0 - coverage + 0.28, bank);
	if (mass <= 0.0) {
		return 0.0;   // fuera del banco el detalle solo escalaría 0: nos saltamos su FBM.
	}

	// Jirones de detalle: ruido más fino que viaja algo más rápido, para que el banco respire.
	// 1 octava basta para el vaivén de los bordes; 2 apenas se distinguía y costaba el doble.
	float detail = _fbm(noise_pos * 4.3 + wind_dir * (wind_offset * 1.6), 1);
	mass *= mix(0.55, 1.0, detail);

	return height_grad * mass * occ_mult;
}

void march_fog(
	vec3 ro, vec3 rd, float max_dist,
	vec3 planet_center, float fog_min_r, float fog_max_r,
	float density, float coverage, float noise_scale,
	vec3 wind_dir, float wind_offset,
	vec3 sun_dir, float sun_intensity, vec3 fog_color,
	int steps, float jitter, float view_distance,
	Sky sky, vec3 up_obs, float inv_flat, float planet_radius,
	out vec3 out_color, out float out_trans
) {
	out_color = vec3(0.0);
	out_trans = 1.0;

	vec2 outer = ray_sphere(planet_center, fog_max_r, ro, rd);
	if (outer.y <= 0.0) return;

	float t0 = outer.x;
	float t1 = outer.x + outer.y;

	// Recorte por la esfera interior (suelo de la niebla), igual que las nubes.
	vec2 inner = ray_sphere(planet_center, fog_min_r, ro, rd);
	if (inner.y > 0.0) {
		float ro_r = length(ro - planet_center);
		if (ro_r < fog_min_r) {
			t0 = max(t0, inner.x + inner.y);
		} else {
			t1 = min(t1, inner.x);
		}
	}

	t0 = max(t0, 0.0);
	t1 = min(t1, max_dist);
	// Distancia de visibilidad de la niebla: no marchamos más allá. Acota la niebla a un manto
	// local (la niebla a ras de suelo no se ve lejos), de modo que SIEMPRE cabe dentro de la
	// rejilla de oclusión → las cuevas se vacían sin tocar la resolución/tamaño de la rejilla.
	if (view_distance > 0.0) t1 = min(t1, view_distance);
	if (t1 <= t0 + 0.001) return;

	// El setup de la oclusión de cueva no depende del punto: se paga una vez por rayo.
	FogOcclusion occ = make_fog_occlusion();

	int fog_steps = clamp(steps, 1, 64);
	float step_size = (t1 - t0) / float(fog_steps);
	float t = t0 + step_size * jitter;

	for (int i = 0; i < fog_steps && t < t1; i++) {
		vec3 p = ro + rd * t;
		float d = sample_fog_density(p, planet_center, fog_min_r, fog_max_r,
		                             coverage, noise_scale, wind_dir, wind_offset, occ);
		// Desvanecido suave hacia la distancia de visibilidad para que no haya un corte duro al
		// llegar a view_distance (el banco se difumina en vez de terminar en una pared).
		if (view_distance > 0.0) {
			d *= 1.0 - smoothstep(view_distance * 0.6, view_distance, t);
		}
		if (d > 0.0001) {
			// Iluminación simple: la luz del sol que llega al banco (con el color que le deja el aire:
			// niebla de amanecer naranja), más la del cielo, que dura un poco tras el ocaso, más el
			// resplandor nocturno y la luna.
			vec3 up_p = normalize(p - planet_center);
			float h_p = length(p - planet_center) - planet_radius;
			float mu_sun = flat_cos(up_p, up_obs, inv_flat, sun_dir);
			vec3 sun_col = sky_sun_transmittance(sky, h_p, mu_sun);
			float sky_l = sky_ambient_level(mu_sun);
			// El color del ocaso es luz de sol directa: con el cielo tapado (P(23).w, atmosphere_scatter,
			// ~1 despejado y ~0 en tormenta) se queda en su luminancia → bruma de tormenta gris.
			float sun_lum = dot(sun_col, vec3(0.2126, 0.7152, 0.0722));
			sun_col = mix(vec3(sun_lum), sun_col, clamp(P(23).w, 0.0, 1.0));

			// Ambiente nocturno (P(26).y): de noche la niebla no se apaga del todo — la sigue
			// iluminando el resplandor del cielo. Es un valor ABSOLUTO, NO escalado por
			// sun_intensity (escalado, con sun_intensity 20 se leía como niebla BLANCA en plena
			// oscuridad). Queda NEUTRO a propósito: el viraje azul de la noche lo pone el paso de
			// Purkinje del final, que a esta luminancia actúa de lleno.
			float night_ambient = max(P(26).y, 0.0) * (1.0 - min(sky_l, 1.0));

			vec3 lit = fog_color * ((sun_col * 0.75 + sky.ms_tint * (0.25 * sky_l)) * (sun_intensity * 0.16)
				+ vec3(night_ambient));
			// Luz de luna (P(33)/P(34)): de noche el banco se ilumina con ella igual que con el sol.
			if (P(33).w > 0.0) {
				vec3 moon_col = sky_sun_transmittance(sky, h_p, flat_cos(up_p, up_obs, inv_flat, normalize(P(33).xyz)));
				lit += fog_color * P(34).rgb * moon_col * (sun_intensity * 0.16 * P(33).w * (1.0 - min(sky_l, 1.0)));
			}

			float s_trans = exp(-d * step_size * density * 0.02);
			out_color += out_trans * (1.0 - s_trans) * lit;
			out_trans *= s_trans;

			if (out_trans < 0.01) { out_trans = 0.0; break; }
		}
		t += step_size;
	}
}


float density_at_point(
	vec3 p,
	vec3 planet_center,
	float planet_radius,
	float atmo_radius,
	float density_falloff
) {
	float h = length(p - planet_center) - planet_radius;
	float thickness = max(atmo_radius - planet_radius, 0.001);
	float h01 = clamp(h / thickness, 0.0, 1.0);
	return exp(-h01 * density_falloff) * (1.0 - h01);
}


float optical_depth_points(
	vec3 ro,
	vec3 rd,
	float ray_length,
	vec3 planet_center,
	float planet_radius,
	float atmo_radius,
	float density_falloff,
	int points
) {
	vec3 p = ro;
	float step_size = ray_length / float(points - 1);
	float od = 0.0;
	for (int i = 0; i < points; i++) {
		od += density_at_point(p, planet_center, planet_radius, atmo_radius, density_falloff) * step_size;
		p += rd * step_size;
	}
	return od;
}

float optical_depth(
	vec3 ro,
	vec3 rd,
	float ray_length,
	vec3 planet_center,
	float planet_radius,
	float atmo_radius,
	float density_falloff
) {
	return optical_depth_points(ro, rd, ray_length, planet_center, planet_radius, atmo_radius,
		density_falloff, NUM_OPTICAL_DEPTH_POINTS);
}

vec3 calculate_light(
	vec3 ro,
	vec3 rd,
	float ray_length,
	vec3 original_color,
	vec3 sun_dir,
	vec3 planet_center,
	float planet_radius,
	float atmo_radius,
	float density_falloff,
	Sky sky,
	float sun_intensity,
	float view_from_space,
	float in_scatter_mult,
	float cloud_min_h,
	float cloud_max_h,
	vec3 up_obs,
	float inv_flat,
	float view_scale,
	float scatter_scale,
	float mie_g
) {
	float step_size = ray_length / float(NUM_IN_SCATTER_POINTS - 1);
	float thick = max(atmo_radius - planet_radius, 1.0);

	// Las fases no cambian a lo largo del rayo.
	float nu = dot(rd, sun_dir);
	float ph_r = phase_rayleigh(nu);
	float ph_m = phase_mie(nu, mie_g);
	vec3 moon_dir = normalize(P(33).xyz);
	float moon_intensity = P(33).w;
	float nu_moon = dot(rd, moon_dir);

	vec3 acc_r = vec3(0.0);
	vec3 acc_m = vec3(0.0);
	vec3 acc_ms = vec3(0.0);
	vec3 moon_r = vec3(0.0);
	vec3 moon_m = vec3(0.0);
	// Espesor óptico de vista acumulado (regla del trapecio) con las mismas muestras del bucle.
	vec3 view_od = vec3(0.0);
	float prev_r = 0.0;
	float prev_m = 0.0;

	vec3 p = ro;
	for (int i = 0; i < NUM_IN_SCATTER_POINTS; i++) {
		vec3 rel = p - planet_center;
		float r = length(rel);
		vec3 up = rel / max(r, EPSILON);
		float h = r - planet_radius;

		// Gate VERTICAL del cielo encapotado: la nube tapa el sol desde ARRIBA, así que solo
		// apaga el velo del aire que tiene debajo. Por encima del techo de la capa el aire recibe
		// luz plena y dispersa normal. Sin esto, `in_scatter_mult` multiplicaba el rayo entero y
		// una tormenta apagaba también la atmósfera por encima de ella — se notaba al volar sobre el
		// frente y al mirar el planeta desde el espacio. La localización HORIZONTAL (solo bajo la
		// celda de tormenta) ya viene aplicada en in_scatter_mult por el llamador.
		float overcast = mix(in_scatter_mult, 1.0, smoothstep(cloud_min_h, cloud_max_h, h));

		float d_r = sky_density(h, thick, density_falloff);
		float d_m = sky_density(h, thick, sky.falloff_m);
		if (i > 0) {
			view_od += (sky.sig_r * (prev_r + d_r) + vec3(sky.sig_me * (prev_m + d_m))) * (0.5 * step_size);
		}
		prev_r = d_r;
		prev_m = d_m;
		vec3 view_t = exp(-view_od * view_scale);
		float w = ((i == 0 || i == NUM_IN_SCATTER_POINTS - 1) ? 0.5 : 1.0) * step_size * overcast;

		float mu = flat_cos(up, up_obs, inv_flat, sun_dir);
		vec3 sun_t = sky_sun_transmittance(sky, h, mu);
		vec3 lit = view_t * sun_t * w;
		acc_r += lit * d_r;
		acc_m += lit * d_m;
		acc_ms += view_t * (sky.sig_r * d_r + vec3(sky.sig_m * d_m)) * (sky_ms_brightness(mu) * w);

		// Cielo de luna: la misma dispersión con la luna como fuente, solo donde el sol ya no
		// ilumina el aire (la luna del juego está comprimida para que la noche se lea y de día
		// añadiría un cielo que no existe). Sin luna (intensidad 0, siempre de día) no cuesta nada.
		if (moon_intensity > 0.0) {
			float night = 1.0 - smoothstep(-0.12, 0.02, mu);
			if (night > 0.0) {
				vec3 moon_t = sky_sun_transmittance(sky, h, flat_cos(up, up_obs, inv_flat, moon_dir));
				vec3 lm = view_t * moon_t * (w * night);
				moon_r += lm * d_r;
				moon_m += lm * d_m;
			}
		}
		p += rd * step_size;
	}

	// La atenuación por cielo encapotado ya va aplicada POR MUESTRA (overcast). Solo toca el término
	// aditivo, no la extinción de lo que hay detrás. La aureola de la luna es su lóbulo de Mie.
	vec3 in_scattered_light = sky.sig_r * acc_r * ph_r + acc_m * (sky.sig_m * ph_m)
		+ acc_ms * sky.ms_tint * sky.ms;
	if (moon_intensity > 0.0) {
		in_scattered_light += (sky.sig_r * moon_r * phase_rayleigh(nu_moon)
			+ moon_m * (sky.sig_m * phase_mie(nu_moon, mie_g))) * (moon_intensity * P(34).rgb);
	}
	in_scattered_light *= sun_intensity * scatter_scale;

	// Desde el espacio: la superficie la ilumina el sol del observador (en órbita, sin filtrar), así
	// que aquí se le aplica el aire que cruza el sol hasta ella: casi blanca bajo el sol, naranja y
	// cada vez más tenue hacia el terminador. En el lado nocturno se oscurece.
	vec3 lit_original = original_color;
	if (view_from_space > 0.5) {
		vec2 planet_hit = ray_sphere(planet_center, planet_radius + 400, ro, rd);
		if (planet_hit.y > 0.0) {
			vec3 surface_pt = ro + rd * planet_hit.x;
			float sn_dot = dot(normalize(surface_pt - planet_center), sun_dir);
			vec3 sun_t = sky_sun_transmittance(sky, 0.0, sn_dot);
			lit_original *= mix(vec3(0.05), sun_t, smoothstep(-0.15, 0.15, sn_dot));
		}
	}

	// Atenuación de lo que había detrás (terreno, objetos, cielo).
	return lit_original * exp(-view_od * view_scale) + in_scattered_light;
}


// Efecto Purkinje: en penumbra los bastones dominan la visión → la escena pierde saturación y vira
// a azul. Se decide por el OBSERVADOR (cámara en lado nocturno), no por píxel, y el peso mesópico
// protege los píxeles brillantes (luna, antorchas, relámpagos), que conservan su color fotópico.
// P(24) = tinte escotópico.rgb + fuerza.w. Es de la vista, no del aire: vale igual para los píxeles
// cuyo rayo no cruza la atmósfera. Aplicado solo a los que la cruzan, en el crepúsculo visto desde
// justo encima del aire su borde cortaba el cielo en seco (estrellas grises dentro, color fuera).
vec3 purkinje(vec3 c, vec3 cam, vec3 center, vec3 sun_dir, float planet_r, float atmo_r) {
	float strength = P(24).w;
	if (strength <= 0.001) return c;
	vec3 rel = cam - center;
	float cam_dist = length(rel);
	// Mismo gradiente ±0.15 del terminador que usa el resto del shader.
	float night = 1.0 - smoothstep(-0.15, 0.05, dot(rel / max(cam_dist, EPSILON), sun_dir));
	// Solo cerca del aire: desde el espacio no hay visión escotópica que simular.
	night *= 1.0 - smoothstep(atmo_r, planet_r * 2.0, cam_dist);
	if (night <= 0.001) return c;
	float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
	float mesopic = 1.0 - smoothstep(0.02, 0.5, lum);
	return mix(c, lum * P(24).rgb, strength * night * mesopic);
}


// ─────────────────────────────────────────────
// AURORA VISTA DESDE FUERA. Desde dentro del aire la pinta el cielo (space_sky.gdshader, en el
// marco del observador); al subir por encima de sus cortinas esa se apaga y entra esta, anclada
// al planeta: una cáscara entre P(39).x y P(39).y sobre la superficie con el óvalo alrededor de
// cada polo, extruido en vertical (cortinas). Se compone delante de las nubes, que quedan debajo.
//   P(38): eje del polo (.xyz) + intensidad (.w; 0 = nada que hacer)
//   P(39): .x = altura del pie de las cortinas, .y = altura del techo, .z = tiempo (s), .w = brillo
//   P(40): color bajo (.rgb) + radio del óvalo (.w, seno de su colatitud), P(41): color alto (.rgb)
// El ruido es el mismo de las cortinas del cielo (nimitz, Shadertoy XtGGRt) a la misma escala en
// metros, para que el paso de una a otra no cambie el grano.
// ─────────────────────────────────────────────
float aurora_tri(float x) { return clamp(abs(fract(x) - 0.5), 0.01, 0.49); }
vec2 aurora_tri2(vec2 p) { return vec2(aurora_tri(p.x) + aurora_tri(p.y), aurora_tri(p.y + aurora_tri(p.x))); }
mat2 aurora_rot(float a) { float c = cos(a), s = sin(a); return mat2(vec2(c, s), vec2(-s, c)); }

float aurora_noise(vec2 p, float t) {
	float z = 1.8;
	float z2 = 2.5;
	float rz = 0.0;
	p *= aurora_rot(p.x * 0.06);
	vec2 bp = p;
	mat2 drift = aurora_rot(t * 0.06);
	for (int i = 0; i < 5; i++) {
		vec2 dg = aurora_tri2(bp * 1.85) * 0.75;
		dg *= drift;
		p -= dg / z2;
		bp *= 1.3;
		z2 *= 0.45;
		z *= 0.42;
		p *= 1.21 + (rz - 1.0) * 0.02;
		rz += aurora_tri(p.x + aurora_tri(p.y)) * z;
		p *= mat2(vec2(-0.95534, -0.29552), vec2(0.29552, -0.95534));
	}
	return clamp(1.0 / pow(rz * 29.0, 1.3), 0.0, 0.55);
}

// Semiancho del óvalo, en seno de la colatitud (su centro va en P(40).w).
const float AURORA_OVAL_W = 0.045;
// Unidad del patrón del cielo en múltiplos de P(39).x: el pie de sus cortinas está a 0.8 unidades.
const float AURORA_UNIT_PER_BASE = 1.25;

// Emisión en el punto `p` (relativo al centro del planeta, `r` = su radio).
vec3 aurora_emission(vec3 p, float r, float r_base, float r_top, vec3 pole, vec3 e1, vec3 e2,
		vec2 oval_shift, vec3 sun_dir, float t) {
	float h01 = (r - r_base) / (r_top - r_base);
	if (h01 <= 0.0 || h01 >= 1.0) return vec3(0.0);
	vec3 n = p / r;
	float sl = dot(n, pole);
	// Lejos del óvalo no hay nada: descarte barato por el seno de la colatitud (|q| sin el
	// desplazamiento ni la ondulación, que suman menos de 0.15).
	float sin_colat = sqrt(max(1.0 - sl * sl, 0.0));
	if (abs(sin_colat - P(40).w) > 0.15 + 2.2 * AURORA_OVAL_W) return vec3(0.0);
	// Solo en la noche del punto: de día el cielo iluminado la tapa.
	float night = smoothstep(0.15, -0.1, dot(n, sun_dir));
	if (night <= 0.0) return vec3(0.0);
	float hemi = sl >= 0.0 ? 1.0 : -1.0;
	// Proyección polar: |q| = seno de la colatitud. El óvalo se desplaza hacia el lado nocturno.
	vec2 q = vec2(dot(n, e1), dot(n, e2) * hemi) - oval_shift * vec2(1.0, hemi);
	float phi = atan(q.y, q.x);
	float wig = 0.035 * sin(3.0 * phi + t * 0.011 + hemi)
		+ 0.018 * sin(7.0 * phi - t * 0.023 + hemi * 2.0)
		+ 0.008 * sin(13.0 * phi + t * 0.05);
	float d = length(q) - (P(40).w + wig);
	float env = exp(-pow(d / AURORA_OVAL_W, 2.0));
	if (env < 0.01) return vec3(0.0);
	// Arcos paralelos dentro del óvalo, como las bandas del cielo.
	float arcs = exp(-pow((fract(d / 0.02 + 0.5) - 0.5) * 3.0, 2.0));
	// Proyección en metros desde el polo, pasada a unidades del patrón del cielo (y su * 1.2).
	vec2 np = vec2(dot(n, e1), dot(n, e2) * hemi) * (r_base / (AURORA_UNIT_PER_BASE * max(P(39).x, 1.0))) * 1.2;
	float curtain = aurora_noise(np, t) * env * mix(0.15, 1.0, arcs);
	// Perfil vertical: borde inferior nítido, verde intenso abajo y violeta tenue arriba.
	float prof = smoothstep(0.0, 0.05, h01) * (0.2 + 0.8 * exp(-h01 * 4.0)) * (1.0 - smoothstep(0.75, 1.0, h01));
	vec3 tone = mix(P(40).rgb, P(41).rgb, smoothstep(0.2, 0.8, h01));
	return tone * (curtain * prof * night);
}

// Suma de la emisión a lo largo de un tramo del rayo.
vec3 aurora_march(vec3 ro, vec3 rd, float t0, float t1, int steps, float jitter, vec3 center,
		float r_base, float r_top, vec3 pole, vec3 e1, vec3 e2, vec2 oval_shift, vec3 sun_dir, float t) {
	if (t1 <= t0 || steps <= 0) return vec3(0.0);
	float dt = (t1 - t0) / float(steps);
	vec3 sum = vec3(0.0);
	for (int i = 0; i < steps; i++) {
		vec3 p = ro + rd * (t0 + (float(i) + jitter) * dt) - center;
		float r = length(p);
		sum += aurora_emission(p, r, r_base, r_top, pole, e1, e2, oval_shift, sun_dir, t);
	}
	return sum * dt;
}

vec3 aurora_shell(vec3 ro, vec3 rd, float t_max, vec3 center, float planet_r, vec3 sun_dir, float jitter) {
	float r_base = planet_r + P(39).x;
	float r_top = planet_r + P(39).y;
	vec2 top = ray_sphere(center, r_top, ro, rd);
	if (top.y <= 0.0) return vec3(0.0);
	float t0 = top.x;
	float t1 = min(top.x + top.y, t_max);
	if (t1 <= t0) return vec3(0.0);
	vec3 pole = normalize(P(38).xyz);
	vec3 e1 = normalize(cross(pole, abs(pole.x) < 0.9 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 0.0, 1.0)));
	vec3 e2 = cross(pole, e1);
	vec2 oval_shift = -vec2(dot(sun_dir, e1), dot(sun_dir, e2)) * 0.04;
	float t = P(39).z;
	// El hueco bajo el pie de las cortinas no se recorre: tramo de entrada y de salida.
	vec2 base = ray_sphere(center, r_base, ro, rd);
	float a1 = base.y > 0.0 ? min(t1, base.x) : t1;
	float b0 = base.y > 0.0 ? max(t0, base.x + base.y) : t1;
	const int STEPS = 40;
	bool two = a1 > t0 && t1 > b0;
	int steps_a = two ? STEPS / 2 : STEPS;
	vec3 sum = aurora_march(ro, rd, t0, a1, steps_a, jitter, center, r_base, r_top, pole, e1, e2, oval_shift, sun_dir, t);
	sum += aurora_march(ro, rd, b0, t1, STEPS - (a1 > t0 ? steps_a : 0), jitter, center, r_base, r_top, pole, e1, e2, oval_shift, sun_dir, t);
	// Normalizada al grosor de la cáscara: una columna vertical vale lo que su perfil.
	// Brillo de una columna vertical; rasante al limbo el rayo cruza muchas cortinas y sale más.
	return sum * (P(39).w * P(38).w / (r_top - r_base));
}


void main() {
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(P(0).xy);
	if (pixel.x >= size.x || pixel.y >= size.y) return;

	// Early-out sin tocar la imagen: el color buffer ya contiene la escena, así que
	// releerla y reescribirla solo quemaría ancho de banda.
	if (P(11).w < 0.5) return;

	vec2 uv = (vec2(pixel) + vec2(0.5)) / vec2(size);

	float planet_radius       = P(0).z;
	float atmo_radius         = P(0).w;
	float density_falloff     = P(5).w;
	float scattering_strength = P(6).w;
	float sun_intensity       = P(7).w;

	vec3 camera_position = P(8).xyz;          // (0,0,0): trabajamos relativo a cámara.
	vec3 planet_center   = P(9).xyz;
	vec3 sun_direction   = normalize(P(10).xyz);
	vec3 wavelengths     = P(11).rgb;         // nm (p.ej. 700, 530, 440)

	// Coeficientes de scattering tipo Rayleigh: (400/λ)^4 * strength.
	vec3 scattering_coefficients = vec3(
		pow(400.0 / max(wavelengths.r, 1.0), 4.0),
		pow(400.0 / max(wavelengths.g, 1.0), 4.0),
		pow(400.0 / max(wavelengths.b, 1.0), 4.0)
	) * scattering_strength;

	// Dirección del rayo en mundo.
	vec3 view_probe = reconstruct_view_position(uv, 0.0001);
	vec3 ray_dir = normalize(view_to_world_dir(view_probe));

	// Ángulo que subtiende un píxel, sacado de la propia proyección: así el LOD del ruido de las
	// nubes sigue a la resolución y al FOV sin parámetro nuevo que mantener sincronizado.
	vec3 probe_dy = reconstruct_view_position(uv + vec2(0.0, 1.0 / float(size.y)), 0.0001);
	float pixel_angle = length(normalize(probe_dy) - normalize(view_probe));

	// Intersección con la atmósfera.
	vec2 atmo = ray_sphere(planet_center, atmo_radius, camera_position, ray_dir);
	float dst_to_atmo      = atmo.x;
	float dst_through_atmo = atmo.y;

	// Profundidad de escena (Godot reverse-Z: cerca ~1, lejos/cielo ~0).
	float depth_sample = texelFetch(depth_texture, pixel, 0).r;
	bool has_scene_depth = depth_sample > 1e-7;

	float scene_t = MAX_FLOAT;
	if (has_scene_depth) {
		vec3 scene_view_position = reconstruct_view_position(uv, depth_sample);
		scene_t = length(scene_view_position);
	} else if (dst_to_atmo > EPSILON) {
		// Sin geometría en el depth buffer (planeta más allá del far plane de la cámara o del
		// view_distance del terreno) el march no tenía dónde pararse y atravesaba el planeta
		// entero: dentro, density_at_point satura al MÁXIMO, así que el in-scatter se disparaba
		// y el cuerpo se veía como una bola blanca quemada. Corta contra la esfera sólida.
		// Solo en esta rama: donde sí hay depth manda el terreno real (con su relieve).
		//
		// Y solo con la cámara FUERA de la atmósfera (dst_to_atmo > 0), que es el único caso que
		// tiene el problema. Desde dentro, los píxeles sin depth bajo el horizonte son la franja
		// que deja la malla de agua al hundirse entre vértices (cuerda vs arco): cortarlos ahí
		// los deja sin velo, con el cielo de fondo mirando hacia abajo → banda negra en el horizonte.
		vec2 solid = ray_sphere(planet_center, planet_radius, camera_position, ray_dir);
		if (solid.y > 0.0 && solid.x > 0.0) {
			scene_t = solid.x;
		}
	}

	vec4 scene_color = imageLoad(color_image, pixel);
	// Ancho angular de un píxel: es la huella con la que el techo filtra su detalle.
	vec4 spread_a = UW_inv_projection * vec4(uv * 2.0 - 1.0, 1.0, 1.0);
	vec4 spread_b = UW_inv_projection * vec4((uv + vec2(1.0 / float(size.x), 0.0)) * 2.0 - 1.0, 1.0, 1.0);
	float pixel_spread = length(normalize(spread_b.xyz / spread_b.w) - normalize(spread_a.xyz / spread_a.w));
	WaterOptics water = uw_trace(uv, ray_dir, scene_t, has_scene_depth, pixel_spread);
	// uw_trace sale antes del bloque de depuración cuando el píxel está seco, así que
	// un modo debug que no cambia NADA es ambiguo: puede ser "el efecto no hace nada"
	// o "la cámara no está en el agua", que son dos problemas distintos y en ficheros
	// distintos. Los píxeles secos se pintan de magenta para que no se confundan.
	if (UW_debug_mode != 0 && !water.wet) {
		// MAGENTA: el pase entero está desactivado (data[12].x). Lo decide la CPU en
		// UnderwaterRenderPass.prepare: _camera_near_water dijo que la cámara no está
		// cerca del agua, o _inside_interior que está en un compartimento seco.
		// NARANJA: el pase está activo, pero el plano de flotación clasifica el píxel
		// como seco, así que el fallo estaría en waterline_point / waterline_normal.
		bool pass_active = water_params.data[12].x >= 0.5;
		vec3 mark = pass_active ? vec3(0.95, 0.45, 0.0) : vec3(0.45, 0.0, 0.45);
		imageStore(color_image, pixel, vec4(mark, scene_color.a));
		return;
	}
	scene_color.rgb *= water.caustic_gain;
	vec3 water_background = scene_color.rgb * water.background_transmission;
	imageStore(occlusion_mask, pixel, vec4(0.0));
	if (water.wet) {
		if (!water.air_visible || max(water.transmission.r, max(water.transmission.g, water.transmission.b)) < 0.005) {
			imageStore(color_image, pixel, vec4(scene_color.rgb * water.transmission + water.scatter + water_background, scene_color.a));
			return;
		}
		camera_position += ray_dir * water.exit_distance;
		// The raster sky contains the actual solar disc, moon and stars. Sample
		// its immutable snapshot along the SAME refracted ray as the atmosphere.
		// Attenuating the original pixel left a sharp, stationary solar circle.
		scene_color.rgb = uw_refracted_background(scene_color.rgb, water);
		ray_dir = water.air_direction;
		scene_t = max(scene_t - water.exit_distance, 0.0);
		atmo = ray_sphere(planet_center, atmo_radius, camera_position, ray_dir);
		dst_to_atmo = atmo.x;
		dst_through_atmo = atmo.y;
	}

	// Máscara de god rays, parte de geometría. Un oclusor cercano se descuenta (P(32).x de
	// referencia): en pantalla tapa muchísimo, pero solo ensombrece el pedacito de aire que tiene
	// detrás, no la columna entera. Se escribe antes del early-out de abajo para que ningún píxel
	// conserve el valor del frame anterior; el bloque de nubes la reescribe.
	// Lo que queda fuera del aire (la luna, otros astros) no ensombrece ningún haz: solo cuentan los
	// oclusores dentro de la atmósfera. El impostor de la luna escribe profundidad a decenas de km y
	// proyectaba una franja oscura desde su disco, alejándose del sol.
	bool beyond_air = dst_through_atmo <= 0.0 || scene_t >= dst_to_atmo + dst_through_atmo - 1.0;
	float geo_mask = beyond_air ? 1.0 : exp(-scene_t / max(P(32).x, 0.1));
	imageStore(occlusion_mask, pixel, vec4(geo_mask));

	// Rayo de cielo: no hay geometría antes de salir de la atmósfera (cielo, luna, astros).
	bool sky_ray = scene_t >= dst_to_atmo + dst_through_atmo - 1.0;

	// Limita el recorrido por el terreno/objetos (clave para que se vea atmósfera sobre el suelo).
	dst_through_atmo = min(dst_through_atmo, max(scene_t - dst_to_atmo, 0.0));

	if (dst_through_atmo <= 0.0) {
		vec3 seen = purkinje(scene_color.rgb, camera_position, planet_center, sun_direction, planet_radius, atmo_radius);
		imageStore(color_image, pixel, vec4(seen * water.transmission + water.scatter + water_background, scene_color.a));
		return;
	}


	vec3 entry_point = camera_position + ray_dir * (dst_to_atmo + EPSILON);

	float view_from_space = dst_to_atmo > EPSILON ? 1.0 : 0.0;

	// Densificación con la altitud: la cáscara de nubes mide cientos de metros y vista
	// radialmente desde el espacio su espesor óptico era mínimo → velos lechosos que
	// transparentaban el océano, en vez de masas opacas (en la realidad esos cientos de
	// metros de nube ya son opacos). Sube la densidad conforme la cámara se aleja del
	// planeta, sin tocar el tuning a pie de suelo. Se usa en nubes Y en su sombra.
	float cam_dist = length(planet_center - camera_position);
	float cloud_density_eff = P(12).z *
		mix(1.0, 2.0, smoothstep(atmo_radius, planet_radius * 2.0, cam_dist));

	// Radios de la cáscara de nubes. Los comparten la sombra al terreno, el gate vertical del
	// in-scatter y el propio march, así que se calculan una vez.
	float cloud_min_r = planet_radius + P(12).x;
	float cloud_max_r = planet_radius + P(12).y;

	// Sombra de las nubes proyectada sobre el terreno visible. Se aplica al color de
	// escena ANTES de la atmósfera, para que el in-scatter se calcule sobre la
	// superficie ya oscurecida. Reutiliza la misma densidad que dibuja las nubes,
	// así la sombra coincide exactamente con lo que se ve arriba.
	float cloud_shadow_strength = P(8).w;
	if (has_scene_depth && P(13).w > 0.5 && cloud_shadow_strength > 0.0) {
		vec3 surface_p = camera_position + ray_dir * scene_t;
		if (length(surface_p - planet_center) < cloud_max_r) {
			float sh_jitter = ign_jitter(pixel, 7.0) - 0.5;
			float trans = cloud_shadow_transmittance(
				surface_p, sun_direction, planet_center,
				cloud_min_r, cloud_max_r,
				P(12).w, cloud_density_eff, P(13).z, P(13).x,
				sh_jitter
			);
			// Solo lado diurno; fundido suave alrededor del terminador.
			float day = smoothstep(-0.05, 0.1,
				dot(normalize(surface_p - planet_center), sun_direction));
			scene_color.rgb *= mix(1.0, trans, cloud_shadow_strength * day);
		}
	}

	// Multiplicador del in-scatter de Rayleigh (velo azul de perspectiva aérea), parámetro propio del
	// clima (P(23).w, atmosphere_scatter): 1 = dispersión plena, 0 = horizonte plomizo sin azul. Se
	// fija por evento en weather_events.json, desligado de cloud_shadow.
	float in_scatter_mult = clamp(P(23).w, 0.0, 1.0);

	// Scatter LOCAL: con agrupación activa (P(15).w > 0) el cielo solo se apaga BAJO la celda de
	// tormenta. Aplicado global, la tormenta desaturaba también las zonas despejadas → parches
	// donde parecía verse a través del cielo. presencia = envolvente en el punto donde el rayo
	// cruza la capa media de nubes; sin agrupación presencia = 1 (comportamiento global clásico).
	float scatter_group = clamp(P(15).w, 0.0, 1.0);
	if (scatter_group > 0.001 && in_scatter_mult < 0.999) {
		float cloud_mid_r = (cloud_min_r + cloud_max_r) * 0.5;
		vec2 mid_hit = ray_sphere(planet_center, cloud_mid_r, camera_position, ray_dir);
		float t_env;
		if (mid_hit.y > 0.0) {
			// Dentro de la esfera media (bajo las nubes) el cruce es la salida (mid_hit.x = 0).
			t_env = (mid_hit.x > 0.0) ? mid_hit.x : mid_hit.y;
		} else {
			// El rayo no cruza la capa (limbo desde el espacio): punto de máxima cercanía.
			t_env = max(dot(planet_center - camera_position, ray_dir), 0.0);
		}
		// ANCLAJE AL PLANETA: recorta al final del segmento realmente sombreado (terreno o
		// salida de la atmósfera). Sin esto, mirando al suelo el cruce con la esfera media
		// caía en las ANTÍPODAS (el rayo la atraviesa por dentro y sale al otro lado), y el
		// punto barría medio planeta al girar la cámara → tinte "pegado a la pantalla".
		// Así, en píxeles de terreno la envolvente se lee EN ese terreno (proyectada sobre
		// la superficie) y solo los píxeles de cielo usan el cruce con la capa de nubes.
		t_env = min(t_env, dst_to_atmo + dst_through_atmo);
		vec3 env_dir = normalize(camera_position + ray_dir * t_env - planet_center);
		float presence = mix(1.0, texture(cloud_group_tex, latlong_uv(env_dir)).r, scatter_group);
		in_scatter_mult = mix(1.0, in_scatter_mult, presence);
	}

	// Marco del cielo. Con la cámara dentro del aire el cielo se calcula como el de un planeta
	// sky_curvature veces mayor (ver MODELO DE CIELO) y se funde con la geometría real al subir:
	// desde el espacio se ve el planeta que hay. frame_w = 1 en superficie, 0 en el techo del aire.
	Sky sky = make_sky(scattering_coefficients, planet_radius, atmo_radius, density_falloff);
	float thick = atmo_radius - planet_radius;
	float cam_h = cam_dist - planet_radius;
	float frame_w = 1.0 - smoothstep(0.3 * thick, thick, cam_h);
	float flat_w = mix(1.0, max(P(37).y, 1.0), frame_w);
	vec3 up_obs = normalize(camera_position - planet_center);
	float cloud_min_h = P(12).x;
	float cloud_max_h = P(12).y;
	// sun_intensity está afinado para que un aire de 3 km luzca desde el suelo; visto desde fuera,
	// ese mismo velo pesaba unas 5 veces lo que refleja el océano (en la Tierra, ~1.6) y el planeta
	// se veía de un cian lavado. Se funde al alejarse, como la densificación de las nubes.
	float scatter_scale = mix(1.0, clamp(P(26).z, 0.0, 1.0), smoothstep(atmo_radius, planet_radius * 2.0, cam_dist));

	// Nubes volumétricas — se aplican antes del scattering atmosférico.
	// 1. Primero calcula la atmósfera sobre la escena original.
	vec3 light;
	if (sky_ray && frame_w > 0.001) {
		// Rayo de cielo en el planeta virtual: mismo observador (altura) y misma dirección respecto
		// a su vertical, y el espesor óptico de vista a escala terrestre (P(37).x), que es lo que
		// satura el horizonte: blanco a mediodía, naranja al ponerse el sol. El terreno se queda con
		// el aire real (su bruma ya está afinada): distinto cielo detrás de la silueta es lo normal.
		float r_v = planet_radius * flat_w;
		float h_v = max(cam_h, 0.0);
		vec3 center_v = camera_position - up_obs * (r_v + h_v);
		// Bajo el horizonte virtual (huecos del terreno o del agua) vale el color del horizonte: el
		// rayo cruzaría el planeta virtual entero.
		float sin_dip = sqrt(h_v * (2.0 * r_v + h_v)) / (r_v + h_v);
		float e = dot(ray_dir, up_obs);
		vec3 rd_v = ray_dir;
		if (e < -sin_dip) {
			vec3 flat_dir = ray_dir - up_obs * e;
			float flat_len = length(flat_dir);
			flat_dir = flat_len > 1e-5 ? flat_dir / flat_len : normalize(cross(up_obs, vec3(0.0, 0.0, 1.0)));
			float e_v = -sin_dip * 0.999;
			rd_v = flat_dir * sqrt(1.0 - e_v * e_v) + up_obs * e_v;
		}
		vec2 hit_v = ray_sphere(center_v, r_v + thick, camera_position, rd_v);
		light = calculate_light(
			camera_position + rd_v * (hit_v.x + EPSILON), rd_v, max(hit_v.y - EPSILON * 2.0, 0.0),
			scene_color.rgb, sun_direction, center_v, r_v, r_v + thick, density_falloff, sky,
			sun_intensity, 0.0, in_scatter_mult, cloud_min_h, cloud_max_h,
			up_obs, 1.0, mix(1.0, max(P(37).x, 1.0), frame_w), scatter_scale, sky.g
		);
	} else {
		float mie_g = (has_scene_depth && !sky_ray) ? TERRAIN_MIE_G : sky.g;
		light = calculate_light(
			entry_point, ray_dir, max(dst_through_atmo - EPSILON * 2.0, 0.0),
			scene_color.rgb, sun_direction, planet_center, planet_radius, atmo_radius,
			density_falloff, sky, sun_intensity, view_from_space, in_scatter_mult,
			cloud_min_h, cloud_max_h, up_obs, 1.0 / flat_w, 1.0, scatter_scale, mie_g
		);
	}

	// 2. Después compón las nubes delante de la atmósfera.
	if (P(13).w > 0.5) {
		vec3  cloud_col;
		float cloud_trans;
		float cloud_dist;

		float cloud_max_dist = min(scene_t, dst_to_atmo + dst_through_atmo);

		// Jitter por píxel: desplaza el origen del march de forma distinta en cada píxel
		// para que los artefactos de escalón no sean coherentes al mover la cámara.
		float cloud_jitter = ign_jitter(pixel, 0.0);

		march_clouds(
			camera_position, ray_dir, cloud_max_dist,
			planet_center, cloud_min_r, cloud_max_r,
			cloud_density_eff, P(12).w,
			P(13).x, P(13).y, P(13).z,
			sun_direction, sun_intensity, planet_radius,
			scattering_coefficients,
			cloud_jitter, pixel_angle,
			sky, up_obs, 1.0 / flat_w,
			cloud_col, cloud_trans, cloud_dist
		);

		// Las nubes ocluyen los god rays. Se toma la transmitancia EN CRUDO, antes de la
		// perspectiva aérea de abajo: esa la abre para fundir las nubes lejanas con la bruma, y
		// con ese valor el horizonte dejaría pasar rayos a través de la capa lejana.
		imageStore(occlusion_mask, pixel, vec4(geo_mask * cloud_trans));

		// Perspectiva aérea sobre las nubes. Se componen DELANTE de la atmósfera, así que sin
		// esto `cloud_col` no recibe extinción ninguna: una nube a varios km se dibujaba a pleno
		// contraste mientras el terreno que tiene detrás sí se llevaba el velo azul entero. Es lo
		// que hacía que la capa llegase al horizonte igual de nítida que sobre tu cabeza y luego
		// terminara en una línea dura, en vez de disolverse en la bruma como el resto de la
		// escena. Reutiliza el mismo optical_depth que usa la atmósfera, así que la nube lejana
		// se funde exactamente hacia el color de bruma que le corresponde a esa distancia.
		if (cloud_dist > 0.0 && cloud_trans < 0.999) {
			float cloud_od = optical_depth(
				camera_position, ray_dir, cloud_dist,
				planet_center, planet_radius, atmo_radius, density_falloff
			);
			vec3 cloud_ext = exp(-cloud_od * scattering_coefficients);
			// El color propio de la nube se extingue y su opacidad se va abriendo, de modo que lo
			// que asoma por detrás es `light` — que ya ES el cielo con su in-scatter a esa
			// distancia, o sea la bruma correcta. Sin término aditivo aparte.
			cloud_col  *= cloud_ext;
			cloud_trans = mix(1.0, cloud_trans, dot(cloud_ext, vec3(1.0 / 3.0)));
		}

		light = light * cloud_trans + cloud_col;
	}

	// 2b. Aurora vista desde fuera: por encima de las nubes, así que va delante de ellas.
	if (P(38).w > 0.0) {
		light += aurora_shell(
			camera_position, ray_dir, dst_to_atmo + dst_through_atmo, planet_center,
			planet_radius, sun_direction, ign_jitter(pixel, 11.0)
		);
	}

	// 3. Niebla a ras de suelo — lo más cercano, se compone delante de todo. Su banco
	//    viaja con el viento, así se ve llegar de lejos en vez de bajar las nubes.
	if (P(17).w > 0.5 && P(16).z > 0.001) {
		float fog_min_r = planet_radius + P(16).x;
		float fog_max_r = planet_radius + P(16).y;

		vec3  fog_col;
		float fog_trans;

		float fog_max_dist = min(scene_t, dst_to_atmo + dst_through_atmo);
		float fog_jitter = ign_jitter(pixel, 3.0);

		march_fog(
			camera_position, ray_dir, fog_max_dist,
			planet_center, fog_min_r, fog_max_r,
			P(16).z, P(16).w, P(18).x,
			P(14).xyz, P(18).y,
			sun_direction, sun_intensity, P(17).rgb,
			int(P(18).z), fog_jitter, P(18).w,
			sky, up_obs, 1.0 / flat_w, planet_radius,
			fog_col, fog_trans
		);

		light = light * fog_trans + fog_col;
	}

	// 4. Efecto Purkinje (ver purkinje()).
	light = purkinje(light, camera_position, planet_center, sun_direction, planet_radius, atmo_radius);

	if (water.wet) light = uw_surface_radiance(light);
	imageStore(color_image, pixel, vec4(light * water.transmission + water.scatter + water_background, scene_color.a));
}
