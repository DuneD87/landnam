shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Tablazón del casco naval sobre una foto de tablas (wood_floor_deck de Poly Haven, CC0): color,
// normales, rugosidad y altura del mismo escaneo. Cada tabla toma una fila de la foto al azar y su
// propio desplazamiento a lo largo, así que el mismo nudo no se repite por el casco. Las juntas entre
// tracas son las de la foto; las testas entre tablas, escalonadas de una traca a otra, se dibujan aquí.
// El relieve es parallax por capas sobre el mapa de altura: las juntas tienen hondura al mirarlas de
// lado. Lo único que pone el shader encima de la foto es el tono de cada zona: el casco por fuera, la
// bodega (más clara y limpia) y la barandilla (la regala y una franja bajo ella, por los dos lados,
// como un solo madero untado y pulido por las manos). Qué cara es cuál lo dice CUSTOM0, que pone
// NavalHullMesh.surface_custom por celda.
// Las tracas salen de la posición en la grid (metros) y no de las UV planas de cada cara: en los
// costados la junta es una altura, igual en todas las facetas de la proa y del pantoque, y en las
// caras tumbadas se reparten a lo ancho de la manga. UV2 lleva el eje de eslora de la pieza (x, z de
// la grid); lo pone ChunkMeshBuilder por bloque.

uniform sampler2D planks_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D planks_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D planks_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D planks_height : hint_default_white, filter_linear_mipmap, repeat_enable;
// Metros que cubre la foto a lo ancho de sus 12 tablas (la real mide 1,8 m).
uniform float tile_size = 2.6;
// Más corta que la foto, para que una tabla no enseñe dos veces el mismo tramo.
uniform float plank_length = 2.3;
// Cuánto varía el tono de una tabla a otra, sobre lo que ya varía la foto.
uniform float plank_variation : hint_range(0.0, 1.0) = 0.25;
uniform vec3 gap_color : source_color = vec3(0.035, 0.028, 0.022);
uniform float butt_width = 0.008;
uniform float normal_scale = 0.9;
// Hondura de la junta más honda, en metros. 0 quita el parallax.
uniform float relief_depth = 0.006;
// Capas del parallax: más al mirar de lado, donde el desplazamiento es mayor.
uniform int relief_steps_min = 8;
uniform int relief_steps_max = 20;
uniform float specular : hint_range(0.0, 1.0) = 0.4;

// La foto es un pino barnizado muy naranja: se apaga hacia un marrón de madera vieja, mate.
group_uniforms hull;
uniform float saturation : hint_range(0.0, 1.5) = 0.8;
uniform float brightness : hint_range(0.0, 2.0) = 0.85;
uniform float edge_dirt : hint_range(0.0, 1.0) = 0.15;
uniform float roughness_min : hint_range(0.0, 1.0) = 0.6;
uniform float roughness_max : hint_range(0.0, 1.0) = 0.95;

// Dentro no da el agua ni el sol: madera más clara y limpia.
group_uniforms inside;
uniform float inner_saturation : hint_range(0.0, 1.5) = 0.85;
uniform float inner_brightness : hint_range(0.0, 2.0) = 1.15;
uniform float inner_edge_dirt : hint_range(0.0, 1.0) = 0.1;
uniform float inner_roughness_min : hint_range(0.0, 1.0) = 0.65;
uniform float inner_roughness_max : hint_range(0.0, 1.0) = 0.95;

// Regala y franja de barandilla: un madero sin juntas, untado y apenas satinado por las manos.
group_uniforms rail;
// No más alta que NavalHullMesh.RAIL_REACH, hasta donde se busca la regala.
uniform float rail_band = 0.3;
uniform float rail_length = 2.4;
uniform vec3 rail_tint : source_color = vec3(1.0);
uniform float rail_saturation : hint_range(0.0, 1.5) = 0.7;
uniform float rail_brightness : hint_range(0.0, 2.0) = 0.55;
uniform float rail_roughness_min : hint_range(0.0, 1.0) = 0.55;
uniform float rail_roughness_max : hint_range(0.0, 1.0) = 0.85;
group_uniforms;

const int ROWS = 12;
// Centro de cada junta de la foto en v, medido en su mapa de normales (punto medio del bisel). Las
// tablas no miden todas lo mismo: cortar a doceavos dejaba asomar el canto de la tabla vecina.
const float SEAMS[13] = {0.001709, 0.084229, 0.167236, 0.25, 0.335693, 0.419189, 0.501465,
	0.58374, 0.668213, 0.751953, 0.836182, 0.920898, 1.001709};
// Margen en v para un madero sin juntas: se queda dentro de su tabla de la foto, lejos del bisel.
const float INNER_MARGIN = 0.006;
// Rugosidad de la foto entre sus percentiles 5 y 95: se reparte entre el mínimo y el máximo de cada zona.
const vec2 PHOTO_ROUGHNESS = vec2(0.36, 0.66);
const int RAIL_CAP = 16;

varying vec2 plank_uv;
varying float grid_y;
// 0 casco por fuera, 1 bodega, 2 regala (la cara de arriba de la pared).
varying flat float side;
// Altura de la regala que corona la pared de la cara; enorme si no es una pared o queda lejos.
varying flat float rail_top;

struct Plank {
	vec2 uv;
	vec2 id;
	float along_f;
	float across_f;
};


float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Tabla de la tablazón bajo un punto (metros de tabla): su fila de la foto con su desplazamiento, y
// dónde cae el punto dentro de ella.
Plank plank_at(vec2 p) {
	Plank k;
	float plank_w = tile_size / float(ROWS);
	float strake = floor(p.y / plank_w);
	k.across_f = fract(p.y / plank_w);
	float along_s = (p.x + hash12(vec2(strake, 7.3)) * plank_length) / plank_length;
	k.along_f = fract(along_s);
	k.id = vec2(strake, floor(along_s));
	int row = min(int(hash12(k.id) * float(ROWS)), ROWS - 1);
	k.uv = vec2(p.x / tile_size + hash12(k.id + vec2(5.0, 91.0)), mix(SEAMS[row], SEAMS[row + 1], k.across_f));
	return k;
}

// Hondura bajo la cara en un punto, en metros: la del escaneo y la de la testa, que la foto no trae.
// textureGrad con las derivadas de la coordenada continua: el salto de fila en cada junta haría
// elegir el mip más borroso en esa línea, y dentro de un bucle no hay derivadas implícitas.
float plank_depth(vec2 p, vec2 gx, vec2 gy) {
	Plank k = plank_at(p);
	float h = textureGrad(planks_height, k.uv, gx, gy).r;
	float d_butt = min(k.along_f, 1.0 - k.along_f) * plank_length;
	h = min(h, smoothstep(butt_width * 0.5, butt_width + 0.006, d_butt));
	return (1.0 - h) * relief_depth;
}

// Parallax por capas: avanza por el rayo de la vista bajo la cara hasta cruzar la altura, y afina entre
// las dos últimas capas. view_ts es la vista en (a lo largo, a lo ancho, normal).
vec2 parallax(vec2 p, vec3 view_ts, vec2 gx, vec2 gy) {
	float layers = mix(float(relief_steps_max), float(relief_steps_min), clamp(view_ts.z, 0.0, 1.0));
	float layer = relief_depth / layers;
	// A ras de la cara el desplazamiento crece sin límite: se corta como a 78°.
	vec2 delta = -view_ts.xy / max(view_ts.z, 0.2) * layer;
	float ray = 0.0;
	float depth = plank_depth(p, gx, gy);
	vec2 prev_p = p;
	float prev_gap = depth;
	for (int i = 0; i < relief_steps_max; i++) {
		if (ray >= depth || float(i) >= layers) {
			break;
		}
		prev_p = p;
		prev_gap = depth - ray;
		p += delta;
		ray += layer;
		depth = plank_depth(p, gx, gy);
	}
	float after = depth - ray;
	float w = after / min(after - prev_gap, -1e-6);
	return mix(p, prev_p, clamp(w, 0.0, 1.0));
}

// Cobertura de una línea de media anchura `half_w` a distancia `d`, con `fw` metros por píxel. Cuando el
// píxel abarca medio periodo se queda en la cobertura media, en vez de parpadear con la distancia.
float line_coverage(float d, float half_w, float fw, float period) {
	float sharp = 1.0 - smoothstep(half_w - fw, half_w + fw, d);
	return mix(sharp, 2.0 * half_w / period, smoothstep(0.25, 1.0, 2.0 * fw / period));
}

vec3 grade(vec3 albedo, float sat, float bright, float tone, float tone2) {
	float lum = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
	albedo = mix(vec3(lum), albedo, sat * mix(1.0 - 0.25 * plank_variation, 1.0 + 0.15 * plank_variation, tone2));
	return albedo * bright * mix(1.0 - 0.4 * plank_variation, 1.0 + 0.25 * plank_variation, tone);
}


void vertex() {
	vec3 keel = vec3(UV2.x, 0.0, UV2.y);
	keel = dot(keel, keel) > 0.25 ? normalize(keel) : vec3(0.0, 0.0, 1.0);
	vec3 beam = cross(vec3(0.0, 1.0, 0.0), keel);
	// Las tablas van a lo largo de la eslora salvo en las caras que miran a proa o popa (espejo,
	// extremos abiertos), donde corren de costado a costado. Las juntas son alturas salvo en las
	// caras tumbadas (fondo, plan, regala), donde se reparten a lo ancho de la manga.
	vec3 along = abs(dot(NORMAL, keel)) < 0.72 ? keel : beam;
	vec3 across = abs(NORMAL.y) < 0.72 ? vec3(0.0, 1.0, 0.0) : beam;
	plank_uv = vec2(dot(VERTEX, along), dot(VERTEX, across));
	grid_y = VERTEX.y;
	// La v de la foto crece con `across`, y en Godot el verde del mapa de normales apunta a -v.
	TANGENT = normalize(along - NORMAL * dot(along, NORMAL));
	BINORMAL = -normalize(across - NORMAL * dot(across, NORMAL));

	// Sin CUSTOM0 (tamaño de celda 0) todo es casco por fuera.
	int bits = int(CUSTOM0.r + 0.5);
	side = 0.0;
	if (NORMAL.y > 0.9 && (bits & RAIL_CAP) != 0) {
		side = 2.0;
	} else if (NORMAL.y > 0.35) {
		// Hacia arriba solo miran el plan y el pantoque por dentro: el casco abierto no tiene techo.
		side = 1.0;
	} else if (NORMAL.y > -0.35) {
		int bit = abs(NORMAL.x) >= abs(NORMAL.z) ? (NORMAL.x > 0.0 ? 1 : 2) : (NORMAL.z > 0.0 ? 4 : 8);
		side = (bits & bit) != 0 ? 1.0 : 0.0;
	}
	rail_top = abs(NORMAL.y) < 0.72 && CUSTOM0.b > 0.0 ? CUSTOM0.g : 1.0e6;
}


void fragment() {
	float to_top = rail_top - grid_y;
	bool rail = side > 1.5 || to_top < rail_band;
	bool inside = !rail && side > 0.5;
	vec2 gx = dFdx(plank_uv) / tile_size;
	vec2 gy = dFdy(plank_uv) / tile_size;
	float fw_along = fwidth(plank_uv.x);

	vec2 uv;
	vec2 id;
	float along_f;
	float seg_length;
	float d_edge = 1.0;
	if (rail) {
		// Un madero a todo el alto de la franja, con los empalmes en el mismo sitio por dentro, por fuera
		// y por arriba. En la regala la v va y vuelve de canto a canto: al cruzar de celda en la curva
		// de la proa no aparece una junta.
		float across_f = side > 1.5 ? abs(fract(plank_uv.y / rail_band * 0.5) * 2.0 - 1.0)
			: clamp(1.0 - to_top / rail_band, 0.0, 1.0);
		seg_length = rail_length;
		float along_s = plank_uv.x / rail_length;
		along_f = fract(along_s);
		id = vec2(-1.0, floor(along_s));
		int row = min(int(hash12(id) * float(ROWS)), ROWS - 1);
		uv = vec2(plank_uv.x / tile_size + hash12(id + vec2(5.0, 91.0)),
			mix(SEAMS[row] + INNER_MARGIN, SEAMS[row + 1] - INNER_MARGIN, across_f));
		if (side < 1.5) {
			d_edge = rail_band - to_top;
		}
	} else {
		vec2 p = plank_uv;
		if (relief_depth > 0.0) {
			vec3 view = normalize(-VERTEX);
			p = parallax(p, vec3(dot(view, TANGENT), dot(view, -BINORMAL), dot(view, NORMAL)), gx, gy);
		}
		Plank k = plank_at(p);
		uv = k.uv;
		id = k.id;
		along_f = k.along_f;
		seg_length = plank_length;
		d_edge = min(k.across_f, 1.0 - k.across_f) * tile_size / float(ROWS);
	}
	float tone = hash12(id + vec2(17.0, 31.0));
	float tone2 = hash12(id + vec2(53.0, 11.0));

	vec3 albedo = textureGrad(planks_albedo, uv, gx, gy).rgb;
	vec3 orm = textureGrad(planks_orm, uv, gx, gy).rgb;
	vec2 normal_xy = (textureGrad(planks_normal, uv, gx, gy).xy * 2.0 - 1.0) * normal_scale;

	float sat = rail ? rail_saturation : (inside ? inner_saturation : saturation);
	float bright = rail ? rail_brightness : (inside ? inner_brightness : brightness);
	float dirt = rail ? 0.0 : (inside ? inner_edge_dirt : edge_dirt);
	vec2 rough = rail ? vec2(rail_roughness_min, rail_roughness_max)
		: (inside ? vec2(inner_roughness_min, inner_roughness_max) : vec2(roughness_min, roughness_max));
	albedo = grade(albedo, sat, bright, tone, tone2);
	if (rail) {
		albedo *= rail_tint;
	}

	float d_butt = min(along_f, 1.0 - along_f) * seg_length;
	albedo *= 1.0 - dirt * (1.0 - smoothstep(0.0, 0.015, min(d_edge, d_butt)));

	float half_butt = butt_width * 0.5;
	float gap = line_coverage(d_butt, half_butt, fw_along, seg_length);
	// Canto redondeado de las testas, como el que la foto ya trae en las juntas largas.
	float bevel_fade = 1.0 - smoothstep(0.3, 1.0, fw_along / 0.012);
	float bevel = (1.0 - smoothstep(half_butt, half_butt + 0.012, d_butt)) * bevel_fade;
	normal_xy.x += (along_f < 0.5 ? -bevel : bevel) * 0.6;

	// Junta entre la última traca y la barandilla.
	if (rail_top < 1.0e5) {
		float fw_y = fwidth(grid_y);
		float d_band = abs(to_top - rail_band);
		gap = max(gap, line_coverage(d_band, half_butt, fw_y, 10.0));
		float band_bevel = (1.0 - smoothstep(half_butt, half_butt + 0.012, d_band))
			* (1.0 - smoothstep(0.3, 1.0, fw_y / 0.012));
		normal_xy.y += (rail ? band_bevel : -band_bevel) * 0.6;
	}

	ALBEDO = mix(albedo, gap_color, gap) * COLOR.rgb;
	ROUGHNESS = mix(mix(rough.x, rough.y, smoothstep(PHOTO_ROUGHNESS.x, PHOTO_ROUGHNESS.y, orm.g)), 1.0, gap);
	SPECULAR = specular;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.25;
	NORMAL_MAP = vec3(clamp(normal_xy, -0.95, 0.95) * 0.5 + 0.5, 1.0);
}
