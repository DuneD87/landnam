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

// --- Flechas de oleaje ---
// Diagnóstico del campo de orilla horneado (WorldMapBaker.bake_shore_field) dibujado sobre el mapa,
// que es la única forma de separar "el campo está mal" de "el agua lo consume mal".
// Cian = ahí manda el swell de mar abierto; amarillo = manda la ola de orilla. El degradado entre
// los dos es el relevo. La flecha apunta hacia donde VIAJA la ola.
uniform sampler2D shore_map : filter_linear, repeat_enable; // xyz = dirección al litoral, w = distancia (m)
uniform bool show_wave_arrows = false;
uniform bool has_shore_map = false;
uniform vec2 map_size_px = vec2(1024.0, 512.0); // tamaño dibujado; fija el paso en pantalla
uniform float arrow_pixels = 38.0;
// Forma de la franja; se copia del material del agua (ver world_map_ui.gd).
uniform float shore_reach = 0.0;
uniform float shore_range = 1200.0;
uniform float shore_fade = 0.5;

// Misma puerta por distancia que gerstner_surface_ctx.
float shore_gate_at(vec4 field, float dist) {
	if (dist <= 1.0) {
		return 0.0;
	}
	float reach = shore_reach > 0.0 ? shore_reach : shore_range;
	return 1.0 - smoothstep(reach * (1.0 - shore_fade), reach, dist);
}
// Marco del oleaje de mar abierto, copiado del material del agua para calcular su misma dirección.
uniform vec3 swell_pole = vec3(0.0, 1.0, 0.0);
uniform vec2 swell_direction = vec2(2.0, 0.0);

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

// Dirección de viaje del oleaje de mar abierto en ese punto. Réplica de swell_direction() en
// gerstner_waves.gdshaderinc: si una cambia, la otra miente.
vec3 open_swell_dir(vec3 d) {
	vec3 pole = normalize(swell_pole);
	vec3 gx = normalize(cross(pole, abs(pole.x) < 0.9 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 0.0, 1.0)));
	vec3 gy = cross(pole, gx);
	vec2 bd = (abs(swell_direction.x) + abs(swell_direction.y) < 1e-4)
		? vec2(1.0, 0.0) : normalize(swell_direction);
	vec3 fixed_dir = normalize(gx * bd.x + gy * bd.y);
	vec3 tangent = fixed_dir - d * dot(fixed_dir, d);
	float len = length(tangent);
	return len > 1e-4 ? -tangent / len : vec3(0.0);
}

// Un vector tangente de mundo a píxeles del mapa. En un equirect un paso en u cubre TAU*R*sin(theta)
// metros y uno en v cubre PI*R: sin corregir por sin(theta) las flechas se tuercen con la latitud.
vec2 world_tangent_to_px(vec3 t, vec2 uv, float sin_theta) {
	float theta = uv.y * PI_;
	float lon = (uv.x - 0.5) * TAU_;
	vec3 e_u = vec3(-sin(lon), 0.0, -cos(lon));                                    // +u = este
	vec3 e_v = vec3(cos(theta) * cos(lon), -sin(theta), -cos(theta) * sin(lon));   // +v = sur
	return vec2(dot(t, e_u) * map_size_px.x / (2.0 * max(sin_theta, 0.001)),
				dot(t, e_v) * map_size_px.y);
}

// Cuña apuntando a +x en coordenadas locales de celda: ancha por detrás y en punta delante, para que
// el sentido se lea sin ambigüedad. 'grow' la engorda, que es como se dibuja el halo oscuro.
float arrow_mask(vec2 q, float grow, float aa) {
	float half_width = 0.42 * clamp((0.75 - q.x) / 1.35, 0.0, 1.0) + grow;
	return (1.0 - smoothstep(half_width, half_width + aa, abs(q.y)))
		* (1.0 - smoothstep(0.75 + grow, 0.75 + grow + aa, q.x))
		* (1.0 - smoothstep(0.60 + grow, 0.60 + grow + aa, -q.x));
}

// Pinta la flecha de la celda a la que pertenece este fragmento. El campo se muestrea SIEMPRE en el
// centro de la celda, no en el fragmento: así la flecha es una sola y no se deforma.
vec3 wave_arrow(vec3 col, vec2 uv) {
	vec2 px = uv * map_size_px;
	vec2 cell = floor(px / arrow_pixels);
	vec2 center_px = (cell + 0.5) * arrow_pixels;
	vec2 center_uv = center_px / map_size_px;

	float depth = sea_height - height_at(center_uv);
	if (depth <= 0.0) {
		return col;
	}

	vec3 d = uv_to_dir(center_uv);
	float sin_theta = max(length(d.xz), 0.001);
	vec4 field = texture(shore_map, center_uv);
	float dist = abs(field.w);

	float gate = shore_gate_at(field, dist);

	// Se dibuja en toda el agua, no solo donde hay litoral: el degradado cian -> amarillo ES el
	// relevo entre las dos familias, y así se ve de un vistazo dónde deja de mandar el mar abierto.
	vec3 tint = mix(vec3(0.35, 0.85, 1.0), vec3(1.0, 0.9, 0.25), gate);

	vec2 forward;
	if (gate > 0.5) {
		// La cresta viaja por -grad(distancia), y ese gradiente se mide a ARROW_PROBE metros, no
		// leyendo el vector de un téxel suelto: a ~90 m por téxel el litoral es dentado y ese vector
		// es casi ruido. Es la misma dirección que gobierna la fase de la ola en el agua.
		float probe = 300.0;
		float du = probe / (TAU_ * body_radius * sin_theta);
		float dv = probe / (PI_ * body_radius);
		float d_e = texture(shore_map, center_uv + vec2(du, 0.0)).w;
		float d_w = texture(shore_map, center_uv - vec2(du, 0.0)).w;
		float d_s = texture(shore_map, center_uv + vec2(0.0, dv)).w;
		float d_n = texture(shore_map, center_uv - vec2(0.0, dv)).w;
		// Componentes del gradiente en el marco (este, sur); el signo menos es "hacia la costa".
		vec2 grad = -vec2(d_e - d_w, d_s - d_n);
		forward = vec2(grad.x * map_size_px.x / (2.0 * sin_theta), grad.y * map_size_px.y);
		// Sin gradiente utilizable (medio de una bahía) se cae al vector crudo antes que mentir.
		if (length(forward) < 1e-5) {
			forward = world_tangent_to_px(field.xyz, center_uv, sin_theta);
		}
	} else {
		forward = world_tangent_to_px(open_swell_dir(d), center_uv, sin_theta);
	}
	if (length(forward) < 1e-5) {
		return col;
	}
	forward = normalize(forward);

	vec2 local = (px - center_px) / (arrow_pixels * 0.5);
	vec2 q = vec2(dot(local, forward), dot(local, vec2(-forward.y, forward.x)));
	float aa = 4.0 / arrow_pixels;

	col = mix(col, vec3(0.02, 0.03, 0.05), arrow_mask(q, 0.07, aa) * 0.85);
	return mix(col, tint, arrow_mask(q, 0.0, aa));
}

// Franja activa de la ola de orilla, por FRAGMENTO. Las flechas van por celda y a poco zoom que
// quites son un pinchazo suelto en una banda mucho más fina que la rejilla; esto enseña su forma
// real. Rojo = hay campo horneado pero la profundidad lo apaga. Verde = ahí manda la ola de orilla.
// Sin tinte = no hay campo, o sea que estás a más de SHORE_RANGE del litoral.
vec3 shore_band(vec3 col, vec2 uv, float depth) {
	vec4 field = texture(shore_map, uv);
	float reach = shore_reach > 0.0 ? shore_reach : shore_range;
	float dist = abs(field.w);
	if (dist <= 1.0 || dist >= reach) {
		return col;
	}
	float gate = shore_gate_at(field, dist);
	vec3 tint = mix(vec3(1.0, 0.15, 0.10), vec3(0.15, 1.0, 0.30), gate);
	return mix(col, tint, 0.30 + 0.30 * clamp(length(field.xyz), 0.0, 1.0));
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

	if (show_wave_arrows && has_shore_map && has_water) {
		if (submerged) {
			col = shore_band(col, uv, depth);
		}
		col = wave_arrow(col, uv);
	}

	COLOR = vec4(col, 1.0);
}
