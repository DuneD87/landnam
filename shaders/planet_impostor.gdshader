// =============================================================================
//  planet_impostor.gdshader
//  Impostor analítico de un cuerpo planetario lejano (ver planet_impostor.gd).
//  El quad es solo el lienzo: la esfera se traza en el fragment contra
//  (sphere_center, sphere_radius), así la silueta es perfecta a cualquier zoom y
//  no depende de la teselación ni del LOD tope del voxel (que degenera en un
//  octaedro cuando el planeta entero cabe en un par de bloques).
//
//  La superficie NO es procedural: sale de 'surface_map', un equirect horneado
//  por planet_impostor_baker.gd con el mismo VoxelGraph y las mismas texturas de
//  bioma que el terreno real. RGB = albedo, A = altura normalizada. Así el
//  impostor y el terreno enseñan el mismo relieve al cruzarse en la transición.
//
//  IMPORTANTE: la esfera virtual NO está donde está el planeta real.
//  planet_impostor.gd la reproyecta a una distancia dentro del far plane de la
//  cámara conservando el tamaño angular, porque los cuerpos lejanos (la luna a
//  ~135k) caen fuera del far=100000 del jugador. Por eso todo el trazado usa los
//  uniforms en world-space y nunca la posición real del planeta.
//
//  light_direction apunta HACIA el sol, igual que en el resto del proyecto
//  (ver planet_lighting.gdshaderinc / tree_impostor.gdshader). NO negarlo.
// =============================================================================
shader_type spatial;
render_mode unshaded, cull_disabled;

// --- Esfera virtual, empujada cada frame por planet_impostor.gd ---
uniform vec3 sphere_center;
uniform float sphere_radius = 1.0;
uniform vec3 light_direction = vec3(0.0, 0.0, 1.0);
// 1 = solo impostor; <1 = mezclándose con el terreno real (recorte por dither).
uniform float fade : hint_range(0.0, 1.0, 0.01) = 1.0;

// --- Superficie horneada ---
// Mapa de alturas equirect que devuelve VoxelGeneratorGraph::bake_sphere_bumpmap, normalizado
// en [0,1] sobre el rango de búsqueda. Solo el canal rojo.
uniform sampler2D height_map : filter_linear, repeat_enable;
uniform bool has_surface_map = false;
uniform vec3 fallback_color : source_color = vec3(0.55, 0.53, 0.5);
// Con estos dos, height_map vuelve a unidades de mundo: h = height_min + r * height_range.
uniform float height_min = 0.0;
uniform float height_range = 1.0;
uniform float body_radius = 1000.0;

// --- Biomas: mismas reglas y mismos valores que planet_biomes.gdshader ---
#define MAX_BIOMES 8
#define MAX_HEIGHTS 24
#define MAX_LATITUDE_RANGES 9

uniform int biome_count = 3;
uniform int textures_per_biome = 3;
uniform float biome_latitude_ranges[MAX_LATITUDE_RANGES];
uniform float max_heights[MAX_HEIGHTS];
uniform int biome_texture_indices[MAX_HEIGHTS];
// Color medio de cada textura de albedo del terreno (lo calcula planet_impostor_baker.gd).
// Ya vienen linealizados desde CPU: 'source_color' no vale como hint en uniforms de array.
uniform vec3 biome_colors[MAX_HEIGHTS];
uniform float biome_transition_smoothness = 1.0;
uniform float transition_smoothness = 1.5;

// --- Iluminación ---
// Ganancia del relieve sobre la pendiente real. 1 = tal cual sale del mapa de alturas.
uniform float relief_strength : hint_range(0.0, 4.0, 0.05) = 1.0;
uniform float terminator_softness : hint_range(0.005, 0.5, 0.005) = 0.03;
// Luz que conserva la cara nocturna (0 = negro puro).
uniform float night_light : hint_range(0.0, 1.0, 0.01) = 0.03;
// Halo atmosférico en el limbo iluminado. 0 en cuerpos sin atmósfera.
uniform float rim_strength : hint_range(0.0, 3.0, 0.01) = 0.0;
uniform vec3 rim_color : source_color = vec3(0.35, 0.55, 1.0);

// Diagnóstico: 0 normal, 1 albedo crudo sin luz, 2 altura del mapa, 3 normal con relieve,
// 4 magenta/verde según haya mapa o no. Separa "el bake no llegó" de "el bake llegó plano".
// OJO: planet_loader.gd lo empuja cada frame desde 'impostor_debug_mode'; cambiarlo AQUÍ no
// sirve de nada, se pisa al frame siguiente. Se toca en el inspector del nodo del planeta.
uniform int debug_mode : hint_range(0, 4) = 0;

varying vec3 world_pos;

const float PI_ = 3.14159265359;
const float TAU_ = 6.28318530718;

const float BAYER[16] = float[16](
	0.0625, 0.5625, 0.1875, 0.6875,
	0.8125, 0.3125, 0.9375, 0.4375,
	0.2500, 0.7500, 0.1250, 0.6250,
	1.0000, 0.5000, 0.8750, 0.3750
);

// Equirect: u por longitud, v por colatitud (v=0 en el polo norte). Debe coincidir
// exactamente con el recorrido de téxeles de planet_impostor_baker.gd::_bake_thread.
vec2 latlong_uv(vec3 d) {
	return vec2(0.5 + atan(d.x, d.z) / TAU_, acos(clamp(d.y, -1.0, 1.0)) / PI_);
}

// Altura en unidades de mundo sobre el radio nominal, igual que la 'height' del shader del
// terreno (length(pos - centro) - radius), que es contra lo que se comparan max_heights.
float sample_height(vec3 d) {
	return height_min + texture(height_map, latlong_uv(d)).r * height_range;
}

// Color del terreno en esa dirección: pesos de bioma por latitud y escalera de max_heights por
// altura. Copia del bloque "Pesos de bioma" y del acumulador de planet_biomes.gdshader, con el
// color medio de cada textura en vez de la muestra triplanar (a esta distancia es lo mismo).
// Sin slope_factor: la pendiente es detalle local que la esfera no representa.
vec3 biome_albedo(vec3 n, float height) {
	float latitude = degrees(asin(clamp(n.y, -1.0, 1.0)));
	vec3 acc = vec3(0.0);
	float total = 0.0;

	for (int b = 0; b < biome_count; b++) {
		float lower_lat = biome_latitude_ranges[b];
		float upper_lat = biome_latitude_ranges[b + 1];
		float center_lat = (lower_lat + upper_lat) * 0.5;
		float span = upper_lat - lower_lat;
		float w = 1.0 - abs(latitude - center_lat) / max(span * biome_transition_smoothness, 0.0001);
		float biome_weight = smoothstep(0.0, 1.0, clamp(w, 0.0, 1.0));
		if (biome_weight < 0.01) {
			continue;
		}

		int offset = b * textures_per_biome;
		for (int j = 0; j < textures_per_biome; j++) {
			float factor;
			if (j == 0) {
				factor = smoothstep(-transition_smoothness, transition_smoothness,
					max_heights[offset] - height);
			} else {
				float lo = max_heights[offset + j - 1];
				float hi = max_heights[offset + j];
				float s1 = smoothstep(-transition_smoothness, transition_smoothness, hi - height);
				float s2 = smoothstep(-transition_smoothness, transition_smoothness, lo - height);
				factor = s1 * (1.0 - s2);
			}
			factor *= biome_weight;
			if (factor < 0.01) {
				continue;
			}
			acc += biome_colors[biome_texture_indices[offset + j]] * factor;
			total += factor;
		}
	}

	if (total <= 0.0) {
		return fallback_color;
	}
	return acc / total;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Recorte ordenado para la banda de transición con el terreno real.
	int bi = int(mod(FRAGCOORD.x, 4.0)) + int(mod(FRAGCOORD.y, 4.0)) * 4;
	if (BAYER[bi] > fade) {
		discard;
	}

	vec3 ro = INV_VIEW_MATRIX[3].xyz;
	vec3 rd = normalize(world_pos - ro);

	// Intersección rayo-esfera: fuera de la silueta no hay planeta que dibujar.
	vec3 oc = ro - sphere_center;
	float b = dot(oc, rd);
	float c = dot(oc, oc) - sphere_radius * sphere_radius;
	float disc = b * b - c;
	if (disc < 0.0) {
		discard;
	}
	float t = -b - sqrt(disc);
	if (t < 0.0) {
		discard;
	}

	vec3 n = normalize((ro + rd * t) - sphere_center);

	vec3 albedo = fallback_color;
	vec3 nrm = n;

	float h0 = 0.0;
	if (has_surface_map) {
		h0 = sample_height(n);
		albedo = biome_albedo(n, h0);

		// Relieve: gradiente de la altura sobre dos tangentes de la esfera. Se toma con
		// offsets angulares en vez de derivadas en UV para no tener que tratar aparte la
		// singularidad de los polos del equirect.
		vec3 up_ref = vec3(0.0, 1.0, 0.0);
		if (abs(n.y) > 0.99) {
			up_ref = vec3(1.0, 0.0, 0.0);
		}
		vec3 t1 = normalize(cross(up_ref, n));
		vec3 t2 = cross(n, t1);
		const float eps = 0.012;              // radianes; ~2 téxeles a 1024 de ancho
		float h1 = sample_height(normalize(n + t1 * eps));
		float h2 = sample_height(normalize(n + t2 * eps));
		// (unidades de mundo por radián) / radio = pendiente real de la superficie.
		vec3 grad = (t1 * (h1 - h0) + t2 * (h2 - h0)) / eps / body_radius;
		nrm = normalize(n - grad * relief_strength);
	}

	// Sin 'return' anticipado: el lenguaje de shaders de Godot no lo admite en fragment().
	vec3 col;
	if (debug_mode == 1) {
		col = albedo;
	} else if (debug_mode == 2) {
		col = vec3(texture(height_map, latlong_uv(n)).r);
	} else if (debug_mode == 3) {
		col = nrm * 0.5 + 0.5;
	} else if (debug_mode == 4) {
		col = has_surface_map ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 1.0);
	} else {
		vec3 sun = normalize(light_direction);
		float ndl = dot(nrm, sun);
		// El terminador global se marca con la normal LISA, para que el relieve no rompa su línea.
		float day = smoothstep(-terminator_softness, terminator_softness, dot(n, sun));
		float diffuse = max(ndl, 0.0);
		float lit = mix(night_light, 1.0, day) * (0.15 + 0.85 * sqrt(diffuse));

		col = albedo * lit;

		if (rim_strength > 0.0) {
			float rim = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
			col += rim_color * rim * rim_strength * day;
		}
	}

	ALBEDO = col;
}
