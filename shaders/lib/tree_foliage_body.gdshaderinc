// =============================================================================
//  tree_foliage_body.gdshaderinc
//  Follaje de los árboles del generador Branching (Tree3D), incluido por
//  vegetation/tree_foliage.gdshader. Doble cara en todos los LODs: muchas tarjetas miran
//  hacia arriba y, vistas de lado o desde abajo, una sola cara vaciaba la copa.
//
//  Las normales ya vienen mezcladas con las de un elipsoide que envuelve la copa y COLOR.r
//  trae la oclusión de la copa: la luz se lee como un volumen, sin el up del planeta ni la
//  oclusión por tarjeta de transparent_foliage_body.
// =============================================================================
#include "res://shaders/lib/planet_lighting.gdshaderinc"
#include "res://shaders/lib/tree_wind.gdshaderinc"
#include "res://shaders/lib/climate.gdshaderinc"
#include "res://shaders/lib/season.gdshaderinc"

uniform sampler2D texture_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0, 0.001) = 0.4;
uniform float saturation : hint_range(0.0, 2.0, 0.01) = 1.0;
// Variación entre árboles: brillo y un giro entre un verde frío y uno cálido.
uniform float tint_variation : hint_range(0.0, 0.5, 0.01) = 0.1;
uniform vec3 variation_cool_tint = vec3(0.88, 1.0, 0.92);
uniform vec3 variation_warm_tint = vec3(1.1, 1.04, 0.8);
uniform float diffuse_wrap : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float transmission_strength : hint_range(0.0, 3.0, 0.01) = 0.9;
uniform float transmission_sharpness : hint_range(1.0, 8.0, 0.1) = 3.0;
uniform vec4 transmission_color : source_color = vec4(1.0, 0.95, 0.6, 1.0);
uniform float transmission_through_shadow : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform float specular_strength : hint_range(0.0, 1.0, 0.01) = 0.2;
uniform float specular_roughness : hint_range(0.0, 1.0, 0.01) = 0.6;
uniform float ao_strength : hint_range(0.0, 1.0, 0.01) = 1.0;
// Parte de la oclusión de copa que también atenúa el sol: sin sombras propias finas, es la
// que separa la cara al sol de la copa de su interior.
uniform float direct_occlusion : hint_range(0.0, 1.0, 0.01) = 0.45;
// Hoja caduca (season.gdshaderinc): brota, amarillea, enrojece y cae con las estaciones. Los
// perennes solo reciben la nieve. leaf_luma_ref y leaf_chroma_ref: luminancia y cromaticidad verde
// (g / (r + g + b)) medias de la hoja de la textura, en lineal; los colores de otoño son los de esa
// hoja media.
uniform bool deciduous = false;
uniform vec4 autumn_early : source_color = vec4(0.92, 0.75, 0.22, 1.0);
uniform vec4 autumn_late : source_color = vec4(0.85, 0.4, 0.12, 1.0);
uniform vec4 autumn_withered : source_color = vec4(0.5, 0.33, 0.17, 1.0);
uniform float leaf_luma_ref = 0.2;
uniform float leaf_chroma_ref = 0.49;
// Umbrales de la máscara hoja/madera de la textura (season_leaf_mask).
uniform vec4 leaf_mask_edges = vec4(0.45, 0.6, -0.25, -0.05);
// Adelanto (negativo) de la brotación de la especie, en fase: el almendro florece en invierno.
uniform float spring_shift = 0.0;
// Flor de los frutales al brotar (alfa 0 = sin flor). Cada tarjeta va de este color al blanco.
uniform vec4 blossom_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);

varying float v_ao;
varying vec2 v_band;
varying vec3 v_tint;
// Nieve del clima frío (por árbol) y la que queda en el fragmento, que light() usa para que la
// luz no atraviese las ramas nevadas.
varying float v_snow_cover;
varying float v_glacier;
varying float v_snow;
// Hoja de la tarjeta (season_card): x = tiene hoja, y = etapa de otoño, z = hoja tierna.
varying vec3 v_season;
// Flor de la tarjeta: x = cuánta (season_blossom), y = mezcla hacia el blanco.
varying vec2 v_blossom;

void vertex() {
	vec3 relative_base = MODEL_MATRIX[3].xyz - planet_position;
	vec3 up = tree_up(relative_base);
	float seed = tree_seed(relative_base, 17u);
	v_band = tree_band_fades(MODEL_MATRIX[3].xyz, MAIN_CAM_INV_VIEW_MATRIX);
	VERTEX += tree_wind_offset(VERTEX, NORMAL, COLOR, UV2, MODEL_MATRIX, up, seed, TIME);
	// Fuera de su banda el árbol se colapsa: triángulos degenerados, sin rasterizar nada.
	float camera_distance = distance(MODEL_MATRIX[3].xyz, MAIN_CAM_INV_VIEW_MATRIX[3].xyz);
	if (min(v_band.x, v_band.y) <= 0.0 || (IN_SHADOW_PASS && tree_shadow_skip(COLOR, UV2, camera_distance))) {
		VERTEX = vec3(0.0);
	}

	vertex_position_global = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	planet_normal = normalize(vertex_position_global - planet_position);

	v_ao = mix(1.0, COLOR.r, ao_strength);
	v_snow_cover = 0.0;
	v_glacier = 0.0;
	if (!IN_SHADOW_PASS) {
		float cold = climate_snow_coldness(relative_base);
		v_snow_cover = climate_snow_cover(cold);
		v_glacier = climate_glacier(cold);
	}
	float hue = tree_seed(relative_base, 53u);
	v_tint = mix(variation_cool_tint, variation_warm_tint, hue)
		* (1.0 + (seed - 0.5) * 2.0 * tint_variation);
	// También en el pase de sombras: la hoja caída deja pasar el sol.
	v_season = vec3(1.0, 0.0, 0.0);
	v_blossom = vec2(0.0);
	if (deciduous) {
		vec2 state = season_leaf_state(relative_base, (tree_seed(relative_base, 71u) - 0.5) * SEASON_TREE_JITTER,
			spring_shift);
		float card = clamp(COLOR.a / 0.9, 0.0, 0.999);
		v_season = season_card(state, card);
		v_ao = mix(v_ao, 1.0, (1.0 - season_leaf_cover(state)) * SEASON_BARE_AO_LIFT);
		if (blossom_color.a > 0.0) {
			v_blossom = vec2(season_blossom(state.x), fract(card * 3.7) * 0.7);
		}
	}
}

void fragment() {
	if (tree_band_discard(v_band, FRAGCOORD.xy)) {
		discard;
	}
	vec4 tex = texture(texture_albedo, UV);
	vec3 color = tex.rgb * albedo_tint.rgb;
	color *= v_tint;
	float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
	ALBEDO = mix(vec3(luma), color, saturation);
	ALPHA = tex.a;
	if (deciduous && (v_season.x < 0.5 || v_season.y > 0.0 || v_season.z > 0.0)) {
		float leaf = season_leaf_mask_wide(tex.rgb, texture(texture_albedo, UV, SEASON_MASK_BLUR_BIAS).rgb,
			leaf_mask_edges);
		// Sin hoja queda la madera de la ramilla.
		if (v_season.x < 0.5) {
			ALPHA *= step(leaf, 0.5);
		} else {
			vec3 leaf_color = season_leaf_color(ALBEDO, v_season, autumn_early.rgb, autumn_late.rgb,
				autumn_withered.rgb, vec2(leaf_luma_ref, leaf_chroma_ref));
			if (v_blossom.x > 0.0) {
				vec3 flower = mix(blossom_color.rgb, SEASON_BLOSSOM_WHITE, v_blossom.y);
				leaf_color = mix(leaf_color, season_flower_color(ALBEDO, flower, leaf_luma_ref), v_blossom.x);
			}
			ALBEDO = mix(ALBEDO, leaf_color, leaf);
		}
	}
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
	ROUGHNESS = specular_roughness;
	SPECULAR = specular_strength;
	// Con cull_disabled el motor voltea la normal del reverso. Aquí la normal es la de la
	// copa, igual por las dos caras: se deshace el volteo.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	AO = v_ao;
	AO_LIGHT_AFFECT = 0.0;
	// Nieve sobre las ramas: la normal ya es la de la copa, así que cubre su parte alta y las
	// ramas horizontales; el grano la reparte en pellas en vez de un casquete liso.
	v_snow = 0.0;
	if (v_snow_cover > 0.001) {
		float facing = dot(normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz), planet_normal);
		v_snow = climate_object_snow(v_snow_cover, v_glacier, facing + 0.12, vertex_position_global - planet_position);
		ALBEDO = mix(ALBEDO, CLIMATE_SNOW_ALBEDO, v_snow);
		ROUGHNESS = mix(ROUGHNESS, 0.85, v_snow);
	}
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// Envolvente sin normalizar por (1 + wrap)²: a pleno sol la cara iluminada llega a 1.
	float wrapped = max(ndl + diffuse_wrap, 0.0) / (1.0 + diffuse_wrap);
	float toward_sun = max(dot(VIEW, -LIGHT), 0.0);
	float transmission = pow(toward_sun, transmission_sharpness)
		* mix(max(-ndl, 0.0), 1.0, 0.4) * transmission_strength * (1.0 - v_snow);
	float day = LIGHT_IS_DIRECTIONAL
		? planet_light_visibility(normalize((VIEW_MATRIX * vec4(planet_normal, 0.0)).xyz), LIGHT)
		: 1.0;
	float occlusion = mix(1.0, v_ao, direct_occlusion);
	vec3 light_energy = LIGHT_COLOR * day / PI;
	// La luz que atraviesa la copa se difunde entre hojas: la transmisión solo pierde parte
	// de su energía a la sombra de las hojas de encima, o el interior de la copa, visto
	// desde debajo, quedaba negro a mediodía.
	// Solo el sol y la luna: en las luces locales ATTENUATION es también la caída con la
	// distancia, y saltársela iluminaba las hojas en recuadros de la rejilla de luces (las
	// setas de cueva, bajo tierra, teñían de amarillo el follaje de encima).
	float transmitted = LIGHT_IS_DIRECTIONAL ? mix(ATTENUATION, 1.0, transmission_through_shadow) : ATTENUATION;
	DIFFUSE_LIGHT += vec3(wrapped) * occlusion * ATTENUATION * light_energy
		+ transmission * transmission_color.rgb * v_ao * transmitted * light_energy;
	vec3 half_sum = LIGHT + VIEW;
	vec3 half_vector = half_sum / max(length(half_sum), 0.0001);
	float highlight = pow(max(dot(NORMAL, half_vector), 0.0), mix(64.0, 12.0, ROUGHNESS));
	SPECULAR_LIGHT += highlight * specular_strength * 0.12 * max(ndl, 0.0) * ATTENUATION * light_energy * occlusion;
}
