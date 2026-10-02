// =============================================================================
//  tree_octa_impostor.gdshader
//  Impostor octaédrico de los árboles Branching (banda lejana del instancer). Un quad
//  orientado hacia la cámara (hacia la luz en el pase de sombras) que mezcla las cuatro
//  vistas horneadas más cercanas a la dirección de observación. Se ilumina con el sol real
//  a partir de la normal de copa horneada, con el mismo modelo que el follaje: el bosque
//  lejano se dora, se oscurece y hace sombra igual que el cercano.
//  Atlas: tools/vegetation/bake_tree_impostors.gd. Malla y parámetros:
//  scripts/planet/tree_octa_impostor.gd.
// =============================================================================
shader_type spatial;
render_mode depth_draw_opaque, cull_disabled;

#include "res://shaders/lib/planet_lighting.gdshaderinc"
#include "res://shaders/lib/tree_wind.gdshaderinc"
#include "res://shaders/lib/octahedral.gdshaderinc"
#include "res://shaders/lib/climate.gdshaderinc"
#include "res://shaders/lib/season.gdshaderinc"

uniform sampler2D albedo_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_atlas : filter_linear_mipmap, repeat_disable;
// Hoja caduca: el mismo árbol horneado sin hoja (la madera y las ramillas de las tarjetas). Las
// hojas caídas del atlas normal se sustituyen por lo que hay detrás en este.
uniform bool deciduous = false;
uniform sampler2D bare_albedo_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D bare_normal_atlas : filter_linear_mipmap, repeat_disable;
// Mismos colores de otoño que el follaje.
uniform vec4 autumn_early : source_color = vec4(0.92, 0.75, 0.22, 1.0);
uniform vec4 autumn_late : source_color = vec4(0.85, 0.4, 0.12, 1.0);
uniform vec4 autumn_withered : source_color = vec4(0.5, 0.33, 0.17, 1.0);
uniform float leaf_luma_ref = 0.2;
uniform float leaf_chroma_ref = 0.49;
uniform vec4 leaf_mask_edges = vec4(0.45, 0.6, -0.25, -0.05);
uniform float spring_shift = 0.0;
uniform vec4 blossom_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform int frames = 8;
uniform vec3 center;
uniform float radius = 1.0;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0, 0.01) = 0.5;
// Mismos ajustes que el follaje (tree_foliage_body.gdshaderinc).
uniform float tint_variation : hint_range(0.0, 0.5, 0.01) = 0.1;
uniform vec3 variation_cool_tint = vec3(0.88, 1.0, 0.92);
uniform vec3 variation_warm_tint = vec3(1.1, 1.04, 0.8);
uniform float diffuse_wrap : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float transmission_strength : hint_range(0.0, 3.0, 0.01) = 0.9;
uniform float transmission_sharpness : hint_range(1.0, 8.0, 0.1) = 3.0;
uniform vec4 transmission_color : source_color = vec4(1.0, 0.95, 0.6, 1.0);
uniform float transmission_through_shadow : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform float ao_strength : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float direct_occlusion : hint_range(0.0, 1.0, 0.01) = 0.45;
// Ajustes de la sombra del impostor. Medidos contra la geometría en la misma vista (misma
// media de color a mediodía y al atardecer, ±3 %): sombra completa con el quad por el
// centro de la copa. Quedan como parámetros para recalibrar si cambia el follaje.
// Densidad: fracción de píxeles de la silueta que proyectan sombra (tramado).
uniform float shadow_density : hint_range(0.0, 1.0, 0.01) = 1.0;
// Retroceso del quad de sombra desde el centro de la copa, alejándolo de la luz, en radios.
uniform float shadow_retreat : hint_range(0.0, 1.0, 0.01) = 0.0;
// Entrada de la sombra del impostor (distancia a la cámara). Empieza antes que el impostor
// visible: desde el LOD2 la sombra del árbol la proyecta este quad, visto desde la luz, en
// vez de la geometría (el LOD2 no proyecta; sus ~4.000 árboles eran 12 M de primitivas y
// ~1 ms en las cascadas). 0/0 = la misma entrada que el impostor visible.
uniform float shadow_fade_in_start = 0.0;
uniform float shadow_fade_in_end = 0.0;

varying vec2 v_band;
varying vec3 v_tint;
varying vec2 v_uv0;
varying vec2 v_uv1;
varying vec2 v_uv2;
varying vec2 v_uv3;
varying flat vec4 v_cells01;
varying flat vec4 v_cells23;
varying flat vec4 v_weights;
// x = oclusión, y = nieve del fragmento (las dos las lee light()). Juntas: el shader está en el
// tope de varyings.
varying vec2 v_ao_snow;
// Nieve del clima frío, la misma regla que el follaje con la normal de copa horneada:
// x = cobertura del sitio, y = casquete. zw = estado de la hoja caduca (season_leaf_state).
varying vec4 v_snow_climate;
// Base de la instancia en espacio de vista. En fragment(), MODEL_MATRIX de un MultiMesh es la
// del nodo, sin el transform de la instancia: las normales del atlas salían sin la inclinación
// de cada árbol (la vertical del planeta) y la copa se iluminaba de lado.
varying vec3 v_basis_x;
varying vec3 v_basis_y;
varying vec3 v_basis_z;

vec2 frame_uv(vec2 cell, vec3 offset) {
	vec3 d = hemi_oct_decode(cell / float(frames - 1));
	vec3 right;
	vec3 up;
	oct_frame_basis(d, right, up);
	return vec2(dot(offset, right), -dot(offset, up)) / (2.0 * radius) + 0.5;
}

void vertex() {
	vec3 relative_base = MODEL_MATRIX[3].xyz - planet_position;
	float seed = tree_seed(relative_base, 17u);
	float hue = tree_seed(relative_base, 53u);
	v_tint = mix(variation_cool_tint, variation_warm_tint, hue) * (1.0 + (seed - 0.5) * 2.0 * tint_variation);
	v_snow_climate = vec4(0.0, 0.0, 2.0, 0.0);
	if (!IN_SHADOW_PASS) {
		float cold = climate_snow_coldness(relative_base);
		v_snow_climate.xy = vec2(climate_snow_cover(cold), climate_glacier(cold));
	}
	if (deciduous) {
		v_snow_climate.zw = season_leaf_state(relative_base, (tree_seed(relative_base, 71u) - 0.5) * SEASON_TREE_JITTER,
			spring_shift);
	}
	v_band = tree_band_fades(MODEL_MATRIX[3].xyz, MAIN_CAM_INV_VIEW_MATRIX);
	if (IN_SHADOW_PASS && shadow_fade_in_end > shadow_fade_in_start) {
		float d = distance(MODEL_MATRIX[3].xyz, MAIN_CAM_INV_VIEW_MATRIX[3].xyz);
		v_band.x = smoothstep(shadow_fade_in_start, shadow_fade_in_end, d);
	}

	// Dirección hacia el observador en espacio del objeto, desde el centro de la copa.
	mat3 basis = mat3(MODEL_MATRIX);
	vec3 center_world = (MODEL_MATRIX * vec4(center, 1.0)).xyz;
	vec3 to_viewer = IN_SHADOW_PASS ? -CAMERA_DIRECTION_WORLD : CAMERA_POSITION_WORLD - center_world;
	vec3 local = vec3(dot(basis[0], to_viewer) / dot(basis[0], basis[0]),
		dot(basis[1], to_viewer) / dot(basis[1], basis[1]),
		dot(basis[2], to_viewer) / dot(basis[2], basis[2]));
	vec3 d = normalize(local);
	d.y = max(d.y, 0.0);
	d = normalize(d + vec3(0.0, 0.0001, 0.0));

	vec3 right;
	vec3 up;
	oct_frame_basis(d, right, up);
	vec2 corner = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	vec3 offset = (right * corner.x + up * corner.y) * radius;
	// Adelantado hacia el observador: el quad pasa por el centro de la copa y, visto desde
	// arriba, el terreno recortaba la parte baja del árbol.
	// En el pase de sombras el quad mira a la luz (ver shadow_retreat).
	VERTEX = center + offset + d * (radius * (IN_SHADOW_PASS ? -shadow_retreat : 0.25));
	NORMAL = d;
	if (min(v_band.x, v_band.y) <= 0.0) {
		VERTEX = vec3(0.0);
	}

	vec2 grid = hemi_oct_encode(d) * float(frames - 1);
	vec2 cell0 = clamp(floor(grid), vec2(0.0), vec2(float(frames - 2)));
	vec2 f = clamp(grid - cell0, 0.0, 1.0);
	v_cells01 = vec4(cell0, cell0 + vec2(1.0, 0.0));
	v_cells23 = vec4(cell0 + vec2(0.0, 1.0), cell0 + vec2(1.0, 1.0));
	v_weights = vec4((1.0 - f.x) * (1.0 - f.y), f.x * (1.0 - f.y), (1.0 - f.x) * f.y, f.x * f.y);
	v_uv0 = frame_uv(v_cells01.xy, offset);
	v_uv1 = frame_uv(v_cells01.zw, offset);
	v_uv2 = frame_uv(v_cells23.xy, offset);
	v_uv3 = frame_uv(v_cells23.zw, offset);

	vertex_position_global = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	planet_normal = normalize(vertex_position_global - planet_position);
	mat3 model_view = mat3(MODELVIEW_MATRIX);
	v_basis_x = model_view[0];
	v_basis_y = model_view[1];
	v_basis_z = model_view[2];
}

// season: 0 = sin estaciones (solo el atlas con hoja), 1 = mezcla por manchas, 2 = solo el atlas
// sin hoja. leaf_stage acumula (etapa de otoño, peso) de los píxeles de hoja.
void sample_frame(vec2 cell, vec2 uv, float weight, int season, vec2 state, inout vec4 color,
		inout vec3 normal_ao, inout float total, inout vec2 leaf_stage) {
	if (weight <= 0.0 || any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		return;
	}
	vec2 atlas_uv = (cell + uv) / float(frames);
	vec4 c;
	vec3 n;
	float leaf = 0.0;
	float stage = 0.0;
	if (season == 2) {
		c = texture(bare_albedo_atlas, atlas_uv);
		n = texture(bare_normal_atlas, atlas_uv).rgb;
	} else {
		c = texture(albedo_atlas, atlas_uv);
		n = texture(normal_atlas, atlas_uv).rgb;
		if (season == 1) {
			// Las tarjetas son manchas de ruido en la vista, del tamaño de un ramillete.
			float noise = climate_value_noise(vec3(uv * SEASON_IMPOSTOR_CELLS, dot(cell, vec2(1.0, 8.0)) * 3.7));
			vec3 card = season_card(state, clamp((noise - 0.5) * 1.8 + 0.5, 0.0, 0.999));
			leaf = season_leaf_mask(c.rgb, leaf_mask_edges);
			if (leaf > 0.5 && card.x < 0.5) {
				c = texture(bare_albedo_atlas, atlas_uv);
				n = texture(bare_normal_atlas, atlas_uv).rgb;
				leaf = 0.0;
			}
			stage = card.y;
		}
	}
	float w = weight * c.a;
	color.rgb += c.rgb * w;
	color.a += c.a * weight;
	normal_ao += n * w;
	total += w;
	leaf_stage += vec2(stage, 1.0) * leaf * w;
}

void fragment() {
	if (tree_band_discard(v_band, FRAGCOORD.xy)) {
		discard;
	}
	vec4 color = vec4(0.0);
	vec3 normal_ao = vec3(0.0);
	float total = 0.0;
	vec2 leaf_stage = vec2(0.0);
	vec2 state = v_snow_climate.zw;
	int season = 0;
	if (deciduous && (state.x < 2.0 || state.y > 0.0)) {
		season = season_leaf_cover(state) <= 0.0 ? 2 : 1;
	}
	sample_frame(v_cells01.xy, v_uv0, v_weights.x, season, state, color, normal_ao, total, leaf_stage);
	sample_frame(v_cells01.zw, v_uv1, v_weights.y, season, state, color, normal_ao, total, leaf_stage);
	sample_frame(v_cells23.xy, v_uv2, v_weights.z, season, state, color, normal_ao, total, leaf_stage);
	sample_frame(v_cells23.zw, v_uv3, v_weights.w, season, state, color, normal_ao, total, leaf_stage);
	if (color.a < alpha_scissor_threshold || total <= 0.0) {
		discard;
	}
	if (IN_SHADOW_PASS) {
		float noise = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (noise > shadow_density) {
			discard;
		}
	}
	color.rgb /= total;
	normal_ao /= total;
	vec3 n_object = oct_normal_decode(normal_ao.xy);
	NORMAL = normalize(mat3(v_basis_x, v_basis_y, v_basis_z) * n_object);
	ALBEDO = color.rgb * v_tint;
	if (leaf_stage.y > 0.0) {
		vec3 card = vec3(1.0, leaf_stage.x / leaf_stage.y, clamp(2.0 - state.x, 0.0, 1.0));
		vec3 leaf_color = season_leaf_color(ALBEDO, card, autumn_early.rgb, autumn_late.rgb,
			autumn_withered.rgb, vec2(leaf_luma_ref, leaf_chroma_ref));
		if (blossom_color.a > 0.0) {
			// Sin tarjetas: la media entre el color de la flor y el blanco.
			vec3 flower = mix(blossom_color.rgb, SEASON_BLOSSOM_WHITE, 0.35);
			leaf_color = mix(leaf_color, season_flower_color(ALBEDO, flower, leaf_luma_ref),
				season_blossom(state.x));
		}
		ALBEDO = mix(ALBEDO, leaf_color, leaf_stage.y / total);
	}
	// Sin grano: a esta distancia cada árbol son pocos píxeles y la media es la que cuenta.
	float snow = climate_surface_snow(v_snow_climate.x, n_object.y + 0.12, v_snow_climate.y) * 0.85;
	ALBEDO = mix(ALBEDO, CLIMATE_SNOW_ALBEDO, snow);
	v_ao_snow = vec2(mix(1.0, normal_ao.z, ao_strength), snow);
	AO = v_ao_snow.x;
	AO_LIGHT_AFFECT = 0.0;
	ROUGHNESS = 0.8;
	SPECULAR = 0.1;
}

void light() {
	// El mismo modelo que tree_foliage_body.gdshaderinc (salvo el especular, que en una silueta
	// promediada no tiene sentido): cualquier diferencia se ve como un salto de tono en el relevo.
	float ndl = dot(NORMAL, LIGHT);
	float wrapped = max(ndl + diffuse_wrap, 0.0) / (1.0 + diffuse_wrap);
	float toward_sun = max(dot(VIEW, -LIGHT), 0.0);
	float transmission = pow(toward_sun, transmission_sharpness)
		* mix(max(-ndl, 0.0), 1.0, 0.4) * transmission_strength * (1.0 - v_ao_snow.y);
	float day = LIGHT_IS_DIRECTIONAL
		? planet_light_visibility(normalize((VIEW_MATRIX * vec4(planet_normal, 0.0)).xyz), LIGHT)
		: 1.0;
	float occlusion = mix(1.0, v_ao_snow.x, direct_occlusion);
	vec3 light_energy = LIGHT_COLOR * day / PI;
	// Solo el sol y la luna: en las luces locales ATTENUATION es también la caída con la
	// distancia, y saltársela iluminaba las hojas en recuadros de la rejilla de luces (las
	// setas de cueva, bajo tierra, teñían de amarillo el follaje de encima).
	float transmitted = LIGHT_IS_DIRECTIONAL ? mix(ATTENUATION, 1.0, transmission_through_shadow) : ATTENUATION;
	DIFFUSE_LIGHT += vec3(wrapped) * occlusion * ATTENUATION * light_energy
		+ transmission * transmission_color.rgb * v_ao_snow.x * transmitted * light_energy;
}
