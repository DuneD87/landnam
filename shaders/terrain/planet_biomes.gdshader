shader_type spatial;
render_mode blend_mix;
#include "res://shaders/terrain/terrain_utils.gdshaderinc"
#include "res://shaders/terrain/virtual_texturing.gdshaderinc"

uniform float macro_variation_scale : hint_range(0.0, 0.01) = 0.15;
uniform float macro_variation_strength : hint_range(0.0, 0.5) = 0.18;
uniform float macro_variation_contrast : hint_range(0.5, 3.0) = 1.4;

uniform bool detail_blend_enabled = true;
uniform float detail_scale_multiplier : hint_range(2.0, 16.0) = 5.7;  // primo o irracional, NO 4.0 ni 8.0
uniform float detail_blend_weight : hint_range(0.0, 1.0) = 0.5;

uniform int u_transition_mask;
uniform float radius = 5000.0;
uniform vec3 center;
uniform float water_radius = 29960;
uniform int has_water = 0;
#define MAX_TEXTURES 8
#define MAX_BIOMES 8 // máximo seguro (ajustable si necesitas más)
#define MAX_HEIGHTS 24
#define MAX_LATITUDE_RANGES 9
uniform sampler2D textures[MAX_TEXTURES]: source_color;
uniform sampler2D normal_textures[MAX_TEXTURES];
uniform sampler2D roughness_textures[MAX_TEXTURES];
uniform sampler2D ao_textures[MAX_TEXTURES];
uniform sampler2D height_textures[MAX_TEXTURES];

uniform float max_heights[MAX_HEIGHTS]; // 3 alturas por bioma
uniform int biome_count = 6;
uniform int textures_per_biome = 3;
uniform float biome_latitude_ranges[MAX_LATITUDE_RANGES]; // n+1 rangos para n biomas
uniform int biome_texture_indices[MAX_HEIGHTS];   // índices por bioma
uniform int biome_noise_enabled[MAX_BIOMES];
uniform int biome_noise_source_texture_indices[MAX_BIOMES];
uniform int biome_noise_target_texture_indices[MAX_BIOMES];
uniform float biome_noise_scales[MAX_BIOMES];
uniform float biome_noise_thresholds[MAX_BIOMES];
uniform float biome_noise_smoothness[MAX_BIOMES];
uniform float biome_noise_strengths[MAX_BIOMES];
uniform float biome_noise_seeds[MAX_BIOMES];
uniform int biome_noise_invert[MAX_BIOMES];
uniform float biome_noise_abs_latitude_mins[MAX_BIOMES];
uniform float biome_noise_abs_latitude_maxs[MAX_BIOMES];
uniform float biome_noise_latitude_smoothness[MAX_BIOMES];
uniform sampler2D slope_texture;
uniform sampler2D slope_normal_texture;
uniform sampler2D slope_roughness_texture;
uniform sampler2D slope_height_texture;
uniform sampler2D slope_ao_texture;
uniform float slope_threshold = 0.5;
uniform float slope_smoothness = 0.5;
uniform float transition_smoothness = 0.5;

uniform float biome_transition_smoothness = 1.0; // nueva uniform para suavizar transiciones
uniform float noise_strength = 1.0;
uniform float noise_scale = 0.5;
uniform float height_transition_noise_scale : hint_range(0.0, 0.2) = 0.035;
uniform float height_transition_noise_strength : hint_range(0.0, 200.0) = 35.0;
uniform float height_blend_strength : hint_range(0.0, 1.0) = 0.45;
uniform float height_blend_contrast : hint_range(0.25, 4.0) = 1.8;
uniform float texture_scale = 0.1;
uniform float normal_strength : hint_range(0.0, 4.0) = 2.0;

uniform bool parallax_enabled = false;
uniform float parallax_strength : hint_range(0.0, 3.0) = 0.09;
uniform float parallax_height_center : hint_range(0.0, 1.0) = 0.5;
uniform float parallax_height_contrast : hint_range(0.1, 4.0) = 1.0;
uniform float parallax_min_view_dot : hint_range(0.05, 0.75) = 0.28;
uniform float parallax_max_distance = 10.0;
uniform float parallax_fade_start = 5.0;

uniform float direct_ao_strength : hint_range(0.0, 1.0) = 0.35;
uniform float specular_ao_strength : hint_range(0.0, 1.0) = 0.65;
uniform float terrain_specular_strength : hint_range(0.0, 1.0) = 0.12;
uniform float water_light_depth = 10.0;
uniform float planet_shadow_softness : hint_range(0.0, 0.2) = 0.015;
uniform float specular_aa_strength : hint_range(0.0, 4.0) = 4.0;

uniform float sun_shadow_opacity : hint_range(0.0, 1.0) = 0.7;

varying vec3 world_pos;
varying float height;
varying float v_fragment_ao;
varying vec3 v_planet_up_view;
varying float v_surface_radius;

varying vec3 v_normal_model;
varying vec3 v_vertex_pos_model;
varying float v_caustics;

// Datos de texturing 4-blend del mesher (CUSTOM1): 4 índices + 4 pesos por vértice.
// El ore lo escribe el VoxelGraph (nodos Spots3D -> OutputWeight); aquí solo lo leemos.
varying vec4 v_ore_indices;
varying vec4 v_ore_weights;

#define MAX_ORE_TYPES 8
uniform int ore_count = 0;
uniform sampler2D ore_albedo_textures[MAX_ORE_TYPES] : source_color;
uniform sampler2D ore_normal_textures[MAX_ORE_TYPES];
uniform sampler2D ore_roughness_textures[MAX_ORE_TYPES];

vec4 decode_8bit_vec4(float v) {
	uint i = floatBitsToUint(v);
	return vec4(
		float(i & uint(0xff)),
		float((i >> uint(8)) & uint(0xff)),
		float((i >> uint(16)) & uint(0xff)),
		float((i >> uint(24)) & uint(0xff)));
}

void vertex() {
	int i = 0;
	v_vertex_pos_model = VERTEX; // posición original antes de transvoxel — el atlas fue bakeado con estas coords
	VERTEX = get_transvoxel_position(VERTEX, CUSTOM0, u_transition_mask);
	v_normal_model = NORMAL;

	// INDICES crudos (0..15 por slot); WEIGHTS normalizados a [0,1].
	v_ore_indices = decode_8bit_vec4(CUSTOM1.x);
	v_ore_weights = decode_8bit_vec4(CUSTOM1.y) / 255.0;

	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	height = length(world_pos - center) - radius;
}

void fragment() {
    // 1) Normal del voxel (detail normal map del atlas, con fallback a geometría)
    vec3 normal_model = safe_normalize(v_normal_model, vec3(0.0, 1.0, 0.0));
    get_voxel_normal_view_model(
        v_vertex_pos_model, NORMAL,
        VIEW_MATRIX * MODEL_MATRIX,
        v_normal_model, normal_model
    );
    normal_model = safe_normalize(normal_model, v_normal_model);
    vec3 normal_world = safe_normalize((MODEL_MATRIX * vec4(normal_model, 0.0)).xyz, vec3(0.0, 1.0, 0.0));
    vec3 planet_pos = world_pos - center;
	float distance_to_center = length(planet_pos);
    float underwater = (has_water != 0 && distance_to_center < water_radius) ? 1.0 : 0.0;
    vec3 planet_up = safe_normalize(planet_pos, normal_world);
    v_planet_up_view = safe_normalize((VIEW_MATRIX * vec4(planet_up, 0.0)).xyz, NORMAL);
    v_surface_radius = max(radius + height, radius + 0.001);

    // 2) Parallax opcional. Si esta apagado, no se calcula vista/distancia ni se muestrean height maps para desplazar UVs.
    bool use_parallax = parallax_enabled && parallax_strength > 0.0001 && underwater < 0.5;
    vec3 view_world = normal_world;
    float effective_height = 0.0;
    if (use_parallax) {
        vec3 camera_delta = CAMERA_POSITION_WORLD - world_pos;
        view_world = safe_normalize(camera_delta, normal_world);
        float dist = length(camera_delta);
        float parallax_fade = 1.0 - smoothstep(parallax_fade_start, parallax_max_distance, dist);
        effective_height = parallax_strength * parallax_fade;
        use_parallax = effective_height > 0.00001;
    }

    // 3) Variables de mezcla
    float noise_value = signed_fbm(planet_pos * noise_scale) * noise_strength;
    float transition_noise_active = step(0.0001, height_transition_noise_scale) * height_transition_noise_strength;
    float transition_noise = signed_fbm(planet_pos * height_transition_noise_scale) * transition_noise_active;
    float adjusted_height = height + noise_value;
    float transition_height = adjusted_height + transition_noise;

    float slope = 1.0 - clamp(dot(normal_world, planet_up), -1.0, 1.0);
    float slope_factor = smoothstep(slope_threshold - slope_smoothness,
                                     slope_threshold + slope_smoothness, slope);

    // 4) Slope con UVs base o parallax, segun el toggle.
    TriplanarUVs slope_uvs = compute_triplanar_uvs(planet_pos, texture_scale);
    if (use_parallax) {
        slope_uvs = compute_parallax_uvs_limited(
            slope_height_texture, planet_pos, normal_world, view_world,
            texture_scale, effective_height,
            parallax_height_center, parallax_height_contrast, parallax_min_view_dot
        );
    }
	float final_tightness = 0.0;

    vec3 slope_color    = triplanar_sample_uvs(slope_texture, slope_uvs, normal_world);
    vec4 slope_n_v = triplanar_normal_sample_uvs_v(slope_normal_texture, slope_uvs, normal_world);
	vec3 slope_normal = slope_n_v.xyz;
    float slope_rough   = triplanar_scalar_sample_uvs(slope_roughness_texture, slope_uvs, normal_world);
    float slope_ao_v    = triplanar_scalar_sample_uvs(slope_ao_texture, slope_uvs, normal_world);

    // 5) Pesos de bioma (igual que tenías)
    float biome_weights[MAX_BIOMES];
    for (int i = 0; i < MAX_BIOMES; i++) biome_weights[i] = 0.0;
    float latitude = degrees(asin(planet_up.y));

    for (int i = 0; i < biome_count; i++) {
        float lower = biome_latitude_ranges[i];
        float upper = biome_latitude_ranges[i + 1];
        float center_lat = (lower + upper) * 0.5;
        float range = upper - lower;
        float w = 1.0 - abs(latitude - center_lat) / (range * biome_transition_smoothness);
        biome_weights[i] = smoothstep(0.0, 1.0, clamp(w, 0.0, 1.0));
    }

    // 6) Acumulación con parallax por textura
    vec3 final_color = vec3(0.0);
    vec3 final_normal = vec3(0.0);
    float final_roughness = 0.0;
    float final_ao = 0.0;
    float total_factor = 0.0;

    for (int b = 0; b < biome_count; b++) {
        float biome_weight = biome_weights[b];
        if (biome_weight < 0.01) continue;

        int offset = b * textures_per_biome;

        for (int j = 0; j < textures_per_biome; j++) {
            int tex_index = biome_texture_indices[offset + j];

            // Calcular factor primero — si es despreciable, saltar parallax
            float factor;
            if (j == 0) {
                factor = smoothstep(-transition_smoothness, transition_smoothness,
                                     max_heights[offset + j] - transition_height);
            } else {
                float lower = max_heights[offset + j - 1];
                float upper = max_heights[offset + j];
                float s1 = smoothstep(-transition_smoothness, transition_smoothness, upper - transition_height);
                float s2 = smoothstep(-transition_smoothness, transition_smoothness, lower - transition_height);
                factor = s1 * (1.0 - s2);
            }
            factor *= (1.0 - slope_factor) * biome_weight;
            if (factor < 0.01) continue;  // <-- skip parallax si la textura no aporta

            // --- Noise override: se calcula ANTES del height bias para que el split
            //     hierba/tierra no quede contaminado por el height map de la hierba.
            //     Si height_blend se aplicara antes, override_factor heredaría el bias
            //     de la hierba y luego recibiría también el de la tierra, creando
            //     cortes donde el height map de origen tiene variaciones fuertes. ---
            float base_factor = factor;   // peso pre-bias de la textura fuente
            float override_factor = 0.0;
            int override_tex_index = biome_noise_target_texture_indices[b];
            if (
                biome_noise_enabled[b] != 0 &&
                tex_index == biome_noise_source_texture_indices[b] &&
                override_tex_index >= 0 &&
                override_tex_index < MAX_TEXTURES &&
                override_tex_index != tex_index
            ) {
               	int biome_seed = int(round(biome_noise_seeds[b]));
				float base_scale = biome_noise_scales[b]; // debe ser 1/64 para coincidir con Period 64
				float n      = 0.0;
				float amp    = 1.0;
				float fscale = base_scale;
				float norm   = 0.0;
				for (int o = 0; o < 6; o++) {              // 3 octavas, no 6
				    float v = abs(fast_noise_lite_open_simplex2_3d(planet_pos, fscale, biome_seed + o));
				    n      += (v * -2.0 + 1.0) * amp;
				    norm   += amp;
				    amp    *= 0.1;                          // gain 0.5, no 1.0
				    fscale *= 6.0;                          // lacunarity 2.0, no 3.0
				}
				n = (n / norm) * 0.5 + 0.5; // [0,1] — quítalo si quieres [-1,1] como FastNoise2

				// 3) Threshold + smoothness sobre el ruido ya contrastado.
				//    Como el remap anterior ya normalizó la pendiente, smoothness se comporta
				//    de forma estable aunque cambies strength.
				float t = biome_noise_thresholds[b];
				float s = max(biome_noise_smoothness[b], 0.0001);
				float biome_noise_mask = smoothstep(t - s, t + s, n);

				if (biome_noise_invert[b] != 0) {
				    biome_noise_mask = 1.0 - biome_noise_mask;
				}
                // División limpia: el ratio hierba/tierra lo decide el noise mask,
                // sin contaminación del height map de la fuente.
                override_factor = factor * biome_noise_mask;
                base_factor     = factor - override_factor;
            }

            // UVs (y parallax opcional) para la textura fuente
            TriplanarUVs uvs = compute_triplanar_uvs(planet_pos, texture_scale);
            if (use_parallax) {
                uvs = compute_parallax_uvs_limited(
                    height_textures[tex_index], planet_pos, normal_world, view_world,
                    texture_scale, effective_height,
                    parallax_height_center, parallax_height_contrast, parallax_min_view_dot
                );
            }

            // Height bias aplicado SOLO al peso de la textura fuente (no al override).
            // Así el height map de la hierba solo afecta a la hierba, y el de la tierra
            // solo afecta a la tierra (en la sección de override más abajo).
            if (height_blend_strength > 0.0001 && base_factor > 0.0001) {
                float material_height = triplanar_scalar_sample_uvs(height_textures[tex_index], uvs, planet_up);
                float height_bias = mix(0.35, 1.35, pow(clamp(material_height, 0.0, 1.0), height_blend_contrast));
                base_factor *= mix(1.0, height_bias, height_blend_strength);
            }

            // planet_up como eje de mezcla triplanar: invariante al LOD y a la normal del mesh.
            vec3 c = triplanar_sample_uvs(textures[tex_index], uvs, planet_up);
			if (detail_blend_enabled) {
			    TriplanarUVs uvs_detail = compute_triplanar_uvs(planet_pos, texture_scale * detail_scale_multiplier);
			    vec3 c_detail = triplanar_sample_uvs(textures[tex_index], uvs_detail, planet_up);
			    // Mezcla overlay tipo "detail" — preserva luminancia base
			    c = mix(c, c * c_detail * 2.0, detail_blend_weight);
			}
            vec4 n_v = triplanar_normal_sample_uvs_v(normal_textures[tex_index], uvs, normal_world);

            float r = triplanar_scalar_sample_uvs(roughness_textures[tex_index], uvs, planet_up);
            float ao = triplanar_scalar_sample_uvs(ao_textures[tex_index], uvs, planet_up);

            final_color     += c * base_factor;
            final_normal    += n_v.xyz * base_factor;
			final_tightness += n_v.w   * base_factor;
            final_roughness += r * base_factor;
            final_ao        += ao * base_factor;
            total_factor    += base_factor;

            if (override_factor > 0.001) {
                TriplanarUVs override_uvs = compute_triplanar_uvs(planet_pos, texture_scale);
                if (use_parallax) {
                    override_uvs = compute_parallax_uvs_limited(
                        height_textures[override_tex_index], planet_pos, normal_world, view_world,
                        texture_scale, effective_height,
                        parallax_height_center, parallax_height_contrast, parallax_min_view_dot
                    );
                }

                if (height_blend_strength > 0.0001) {
                    float override_height = triplanar_scalar_sample_uvs(height_textures[override_tex_index], override_uvs, planet_up);
                    float override_height_bias = mix(0.35, 1.35, pow(clamp(override_height, 0.0, 1.0), height_blend_contrast));
                    override_factor *= mix(1.0, override_height_bias, height_blend_strength);
                }

                vec3 override_c = triplanar_sample_uvs(textures[override_tex_index], override_uvs, planet_up);
                vec4 override_n_v = triplanar_normal_sample_uvs_v(normal_textures[override_tex_index], override_uvs, normal_world);
                float override_r = triplanar_scalar_sample_uvs(roughness_textures[override_tex_index], override_uvs, planet_up);
                float override_ao = triplanar_scalar_sample_uvs(ao_textures[override_tex_index], override_uvs, planet_up);

                final_color     += override_c * override_factor;
                final_normal    += override_n_v.xyz * override_factor;
			    final_tightness += override_n_v.w   * override_factor;
                final_roughness += override_r * override_factor;
                final_ao        += override_ao * override_factor;
                total_factor    += override_factor;
            }
        }
    }

    // Slope contribution
    final_color     += slope_color  * slope_factor;
    final_normal    += slope_normal * slope_factor;
    final_roughness += slope_rough  * slope_factor;
    final_ao        += slope_ao_v   * slope_factor;
    total_factor    += slope_factor;

    if (total_factor > 0.0) {
        final_color     /= total_factor;
        final_normal     = apply_normal_strength(normal_world, safe_normalize(final_normal, normal_world), normal_strength);
        final_roughness /= total_factor;
        final_ao        /= total_factor;
	 	float tightness = clamp(final_tightness / total_factor, 0.0, 1.0);
	    float variance  = max(0.0, 1.0 - tightness * tightness);
	    float a2        = final_roughness * final_roughness + variance * specular_aa_strength;
	    final_roughness = clamp(sqrt(a2), 0.04, 1.0);
    } else {
        final_color = vec3(0.5);
        final_roughness = 0.5;
        final_ao = 1.0;
        final_normal = normal_world;
    }

    // 7) Ore overlay leído del voxel (sistema de texturing 4-blend, canal CUSTOM1).
    // El VoxelGraph (OutputWeight layer=type_id) guardó el type_id del ore en un slot de
    // INDICES y su peso en WEIGHTS. Aquí solo lo leemos: lo que se ve es exactamente lo que hay en el
    // voxel (y lo que devuelve el minado). El índice guardado es type_id (1=iron...),
    // la textura del ore es ore_*_textures[type_id - 1].
    if (ore_count > 0) {
        for (int slot = 0; slot < 4; slot++) {
            int ore_id = int(v_ore_indices[slot] + 0.5);
            if (ore_id <= 0) continue;
            int oi = ore_id - 1;
            if (oi >= ore_count) continue;

            float ore_w = clamp(v_ore_weights[slot], 0.0, 1.0);
            if (ore_w > 0.0001) {
                TriplanarUVs ore_uvs = compute_triplanar_uvs(planet_pos, texture_scale);
                vec3 ore_color = triplanar_sample_uvs(ore_albedo_textures[oi], ore_uvs, planet_up);
                vec4 ore_n_v = triplanar_normal_sample_uvs_v(ore_normal_textures[oi], ore_uvs, normal_world);
                float ore_rough = triplanar_scalar_sample_uvs(ore_roughness_textures[oi], ore_uvs, planet_up);
                final_color = mix(final_color, ore_color, ore_w);
                final_normal = mix(final_normal, ore_n_v.xyz, ore_w);
                final_roughness = mix(final_roughness, ore_rough, ore_w);
            }
        }
    }

    // 8) Salidas
	float macro_n = signed_fbm(planet_pos * macro_variation_scale);
	macro_n = sign(macro_n) * pow(abs(macro_n), 1.0 / macro_variation_contrast);
	float macro_factor = 1.0 + macro_n * macro_variation_strength;
	final_color *= macro_factor;
    ALBEDO = final_color;
	NORMAL = normalize((VIEW_MATRIX * vec4(safe_normalize(final_normal, normal_world), 0.0)).xyz);
    ROUGHNESS = final_roughness;
    v_fragment_ao = mix(clamp(final_ao, 0.0, 1.0), 1.0, underwater);
    AO = 1.0;
    AO_LIGHT_AFFECT = 0.0;
    METALLIC = 0.0;
}
void light()
{
    vec3 n = normalize(NORMAL);
    vec3 l = normalize(LIGHT);
    vec3 v = normalize(VIEW);
    float ndotl = clamp(dot(n, l), 0.0, 1.0);

    float ao = clamp(v_fragment_ao, 0.0, 1.0);
    float direct_ao = mix(1.0, ao, direct_ao_strength);
    float specular_ao = mix(1.0, ao, specular_ao_strength);

    float planet_shadow = 1.0;
    float water_light_factor = 1.0;
    float effective_attenuation = ATTENUATION;
    if (LIGHT_IS_DIRECTIONAL) {
        // El sol usa shadow_opacity < 1.0 (relleno barato para sombras de exterior: árboles,
        // items). En el terreno NO queremos esa fuga: las cuevas deben quedar 100% a oscuras.
        // Con shadow_opacity = S, ATTENUATION ∈ [1-S, 1]; remapeamos a [0,1] para recuperar la
        // sombra completa como si la opacidad fuera 1.0. (Si S=1.0 esto es identidad.)
        effective_attenuation = clamp(
            (ATTENUATION - (1.0 - sun_shadow_opacity)) / max(sun_shadow_opacity, 0.0001),
            0.0, 1.0);

        float distance_to_center = length(world_pos - center);
        if (has_water != 0 && distance_to_center < water_radius) {
            float min_distance = water_radius - water_light_depth;
            water_light_factor = smoothstep(min_distance, water_radius, distance_to_center);
        }
        float radius_ratio = clamp(radius / max(v_surface_radius, radius + 0.001), 0.0, 1.0);
        float horizon_cos = -sqrt(max(0.0, 1.0 - radius_ratio * radius_ratio));
        float light_horizon_cos = dot(normalize(v_planet_up_view), l);
        planet_shadow = smoothstep(
            horizon_cos - planet_shadow_softness,
            horizon_cos + planet_shadow_softness,
            light_horizon_cos
        );
    }

    float light_visibility = effective_attenuation * water_light_factor * planet_shadow;

    DIFFUSE_LIGHT += ndotl * light_visibility * direct_ao * LIGHT_COLOR / PI;

    vec3 h = normalize(l + v);
    float ndoth = clamp(dot(n, h), 0.0, 1.0);
    float roughness = clamp(ROUGHNESS, 0.04, 1.0);
    float spec_power = mix(96.0, 4.0, roughness);
    float specular = pow(ndoth, spec_power) * ndotl;
    specular *= light_visibility * terrain_specular_strength * SPECULAR_AMOUNT;
    specular *= specular_ao * (1.0 - roughness);

    SPECULAR_LIGHT += specular * LIGHT_COLOR;
}
