// =============================================================================
//  world_map.gdshader
//  Pinta el mapa mundial que se abre con M (ver world_map_ui.gd).
//
//  La textura del TextureRect es el equirect de ALTURAS horneado por
//  world_map_baker.gd (FORMAT_RF, [0,1] sobre el rango de búsqueda): el color no
//  está precocinado, se calcula aquí por fragmento, así el mapa se ve nítido a
//  cualquier zoom sin guardar una imagen de color aparte.
//
//  La paleta es CARTOGRÁFICA a propósito, no la del terreno. Heredar los biomas
//  daba un mapa donde los polos y todo lo que pasa de 150 m son nieve y el
//  ecuador entero es arena: fiel al terreno e ilegible como mapa. Aquí manda que
//  se distinga de un vistazo dónde acaba el agua y cuánto sube la tierra. Lo
//  único que se hereda del planeta es la latitud del casquete polar.
//
//  'body_map' es el etiquetado de cuerpos de agua: un int32 por téxel
//  reinterpretado como RGBA8, así que hay que muestrearlo SIEMPRE con
//  filter_nearest o los bytes se mezclan y el id sale inventado.
// =============================================================================
shader_type canvas_item;
render_mode unshaded;

// --- Mapa de alturas ---
// Va como uniform propio y NO como el TEXTURE del CanvasItem: los built-ins (TEXTURE,
// TEXTURE_PIXEL_SIZE) solo existen dentro de fragment(), y aquí se muestrea desde funciones
// auxiliares. Usarlos fuera hace que el shader no compile y Godot dibuje el nodo con el material
// por defecto, que con una textura RF se ve como una mancha roja.
uniform sampler2D height_map : filter_linear, repeat_enable;
// 1.0 / resolución del mapa, para los vecinos del sombreado (sustituye a TEXTURE_PIXEL_SIZE).
// (los valores por defecto de un uniform tienen que ser literales: nada de 1.0/1024.0)
uniform vec2 height_texel = vec2(0.0009765625, 0.001953125);

// --- Geometría del planeta ---
uniform float body_radius = 1000.0;
// Con estos dos el téxel vuelve a unidades de mundo: h = height_min + r * height_range.
uniform float height_min = 0.0;
uniform float height_range = 1.0;
// Altura del nivel del mar en esas mismas unidades (relativa al radio nominal).
uniform float sea_height = 0.0;
uniform bool has_water = true;

// --- Agua ---
uniform vec3 shallow_color : source_color = vec3(0.42, 0.72, 0.82);
uniform vec3 deep_color : source_color = vec3(0.05, 0.13, 0.32);
// Profundidad (en metros) a la que el agua ya es del color profundo.
uniform float deep_depth = 400.0;

// --- Tierra: rampa hipsométrica por altura sobre el nivel del mar ---
// Los cinco cortes vienen en METROS y los calcula WorldMapData.land_height_stops() como
// percentiles de la tierra real, no como fracciones de un rango fijo: así cada color cubre un
// trozo parecido de superficie y la rampa no se satura ni por arriba ni por abajo.
uniform float land_stops[5];
uniform vec3 shore_color : source_color = vec3(0.87, 0.83, 0.62);
uniform vec3 lowland_color : source_color = vec3(0.36, 0.60, 0.32);
uniform vec3 upland_color : source_color = vec3(0.58, 0.63, 0.32);
uniform vec3 mountain_color : source_color = vec3(0.58, 0.45, 0.30);
uniform vec3 peak_color : source_color = vec3(0.72, 0.70, 0.68);
uniform vec3 snow_color : source_color = vec3(0.97, 0.98, 1.0);
// Latitud a la que empieza el casquete polar; sale del bioma polar del planeta.
uniform float snow_latitude = 60.0;
uniform float snow_latitude_softness = 8.0;

// Banda árida ecuatorial. La rampa hipsométrica sola pinta el trópico del mismo verde que el resto,
// y en este planeta el bioma central es arena entera: sin esto el mapa no se reconoce contra el
// mundo. La latitud sale del bioma central; con arid_strength a 0 se apaga.
uniform float arid_latitude = 0.0;
uniform float arid_softness = 12.0;
uniform float arid_strength : hint_range(0.0, 1.0, 0.01) = 0.8;
uniform vec3 arid_low_color : source_color = vec3(0.85, 0.76, 0.52);
uniform vec3 arid_high_color : source_color = vec3(0.66, 0.52, 0.35);

// --- Costa ---
// Se traza con derivadas de pantalla, no con una banda de altura: así mide lo mismo en píxeles
// esté la costa en un acantilado o en una marisma, y a cualquier zoom.
uniform vec3 coast_color : source_color = vec3(0.05, 0.09, 0.14);
uniform float coast_width : hint_range(0.0, 4.0, 0.1) = 1.4;

// --- Relieve ---
uniform float relief_strength : hint_range(0.0, 40.0, 0.5) = 8.0;
uniform float shade_strength : hint_range(0.0, 1.0, 0.01) = 0.40;
// El fondo marino es tan rugoso como la tierra, y sombreado a la misma intensidad llena el océano
// de ruido que tapa la silueta de las islas. Se deja apenas insinuado.
uniform float underwater_shade : hint_range(0.0, 1.0, 0.01) = 0.25;
// Dirección de la luz del sombreado en el plano del mapa, (este, sur). Por defecto entra por el
// noroeste, que es la convención cartográfica: los valles se leen como valles.
uniform vec2 shade_light_dir = vec2(-0.7, -0.7);
uniform float shade_light_height : hint_range(0.1, 4.0, 0.05) = 0.9;

// --- Retícula ---
uniform float grid_step_deg = 15.0;
uniform float grid_strength : hint_range(0.0, 1.0, 0.01) = 0.10;
uniform vec3 grid_color : source_color = vec3(1.0, 1.0, 1.0);

// --- Cuerpos de agua ---
// int32 por téxel reinterpretado como RGBA8; 0xFFFFFFFF (todo 255) = tierra.
uniform sampler2D body_map : filter_nearest, repeat_enable;
uniform bool has_body_map = false;
// Cuerpo a resaltar (el de debajo del cursor), o -1 para ninguno.
uniform int highlight_body = -1;
// Diagnóstico: pinta cada cuerpo de agua de un color distinto.
uniform bool debug_bodies = false;

const float PI_ = 3.14159265359;
const float TAU_ = 6.28318530718;

// Inversa exacta de WorldMapData.uv_to_dir (u = 0.5 - atan2(z,x)/TAU, v = acos(y)/PI).
vec3 uv_to_dir(vec2 uv) {
	float theta = uv.y * PI_;
	float lon = (uv.x - 0.5) * TAU_;
	float st = sin(theta);
	return vec3(st * cos(lon), cos(theta), -st * sin(lon));
}

float height_at(vec2 uv) {
	return height_min + texture(height_map, uv).r * height_range;
}

// Id del cuerpo de agua del téxel, o -1 si es tierra. Los cuatro canales son los bytes del
// int32 en little-endian, tal cual los dejó PackedInt32Array.to_byte_array().
int body_at(vec2 uv) {
	vec4 c = texture(body_map, uv);
	return int(round(c.r * 255.0))
		| (int(round(c.g * 255.0)) << 8)
		| (int(round(c.b * 255.0)) << 16)
		| (int(round(c.a * 255.0)) << 24);
}

// Rampa hipsométrica: playa -> llanura -> meseta -> montaña -> roca pelada, y nieve encima según
// latitud y altura. 'altitude' va en metros sobre el nivel del mar.
vec3 land_color(float altitude, float latitude) {
	vec3 col = mix(shore_color, lowland_color,
		smoothstep(land_stops[0], land_stops[1], altitude));
	col = mix(col, upland_color, smoothstep(land_stops[1], land_stops[2], altitude));
	col = mix(col, mountain_color, smoothstep(land_stops[2], land_stops[3], altitude));
	col = mix(col, peak_color, smoothstep(land_stops[3], land_stops[4], altitude));

	// El trópico vira a arena antes de la nieve, así una cumbre tropical sigue pudiendo nevar.
	if (arid_strength > 0.0 && arid_latitude > 0.0) {
		float aridity = 1.0 - smoothstep(arid_latitude - arid_softness,
			arid_latitude + arid_softness, abs(latitude));
		vec3 arid = mix(arid_low_color, arid_high_color,
			smoothstep(land_stops[0], land_stops[3], altitude));
		col = mix(col, arid, aridity * arid_strength);
	}

	// Nieve por dos vías independientes: el casquete polar y la cota alta. Se toma la mayor, para
	// que una cumbre nevada no dependa de la latitud ni un casquete de la altura. La cota arranca
	// en el corte más alto (el 3% de tierra más elevada) y no antes, o nevaría medio planeta.
	float by_latitude = smoothstep(snow_latitude - snow_latitude_softness,
		snow_latitude + snow_latitude_softness, abs(latitude));
	float by_altitude = smoothstep(land_stops[4], land_stops[4] * 2.0, altitude);
	return mix(col, snow_color, max(by_latitude, by_altitude));
}

// Sombreado por pendiente REAL: el gradiente en UV se divide por la distancia de mundo que cubre
// cada unidad de UV, que en un equirect no es la misma en u (se encoge con la latitud) que en v.
float hillshade(vec2 uv, float sin_theta) {
	vec2 ts = height_texel;
	float hl = height_at(uv - vec2(ts.x, 0.0));
	float hr = height_at(uv + vec2(ts.x, 0.0));
	float hu = height_at(uv - vec2(0.0, ts.y));
	float hd = height_at(uv + vec2(0.0, ts.y));

	float east_span = TAU_ * body_radius * max(sin_theta, 0.001);
	float south_span = PI_ * body_radius;
	float slope_e = (hr - hl) / (2.0 * ts.x) / east_span;
	float slope_s = (hd - hu) / (2.0 * ts.y) / south_span;

	vec3 n = normalize(vec3(-slope_e, -slope_s, 1.0 / max(relief_strength, 0.001)));
	vec3 l = normalize(vec3(shade_light_dir, shade_light_height));
	// Normalizado contra la respuesta del terreno llano: lo plano queda a 1.0 exacto y solo las
	// pendientes aclaran u oscurecen.
	float rel = clamp(dot(n, l) / max(l.z, 0.001), 0.0, 2.0);
	return mix(1.0, rel, shade_strength);
}

void fragment() {
	vec2 uv = UV;
	vec3 dir = uv_to_dir(uv);
	float sin_theta = max(length(dir.xz), 0.001);
	float latitude = degrees(asin(clamp(dir.y, -1.0, 1.0)));

	float h = height_at(uv);
	float depth = sea_height - h;      // > 0 sumergido
	bool submerged = has_water && depth > 0.0;

	vec3 col;
	if (submerged) {
		col = mix(shallow_color, deep_color,
			sqrt(clamp(depth / max(deep_depth, 0.001), 0.0, 1.0)));
	} else {
		col = land_color(h - sea_height, latitude);
	}

	// El relieve se aplica también bajo el agua, pero muy atenuado (ver underwater_shade).
	float shade = hillshade(uv, sin_theta);
	col *= submerged ? mix(1.0, shade, underwater_shade) : shade;

	if (has_body_map && submerged) {
		int id = body_at(uv);
		if (debug_bodies && id >= 0) {
			// Hash barato del id a un tono estable; solo es diagnóstico. El desfase evita que el
			// cuerpo 0 (casi siempre el océano) salga gris y se confunda con la tierra.
			float f = float(id) + 0.37;
			vec3 tint = fract(vec3(f * 0.6180339887, f * 0.4142135624, f * 0.7320508076));
			col = mix(col, 0.25 + 0.75 * tint, 0.75);
		}
		if (id == highlight_body) {
			col = mix(col, vec3(1.0, 0.95, 0.55), 0.35);
		}
	}

	// Costa: ancho constante en píxeles gracias a fwidth. Es lo que hace legible la silueta de
	// islas y lagos cuando el sombreado y la rampa se parecen a ambos lados.
	if (has_water && coast_width > 0.0) {
		float aa = max(fwidth(depth), 0.0001);
		float line = 1.0 - smoothstep(0.0, aa * coast_width, abs(depth));
		col = mix(col, coast_color, line * 0.85);
	}

	if (grid_strength > 0.0) {
		vec2 deg = vec2(uv.x * 360.0, uv.y * 180.0) / max(grid_step_deg, 0.001);
		vec2 g = abs(fract(deg - 0.5) - 0.5) / max(fwidth(deg), vec2(0.0001));
		float gline = 1.0 - min(min(g.x, g.y), 1.0);
		col = mix(col, grid_color, gline * grid_strength);
	}

	COLOR = vec4(col, 1.0);
}
