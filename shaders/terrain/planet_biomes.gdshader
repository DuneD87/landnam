shader_type spatial;
render_mode blend_mix;
#include "res://shaders/terrain/terrain_utils.gdshaderinc"
#include "res://shaders/terrain/virtual_texturing.gdshaderinc"

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

uniform sampler2D slope_texture;
uniform sampler2D slope_normal_texture;
uniform sampler2D slope_roughness_texture;
uniform sampler2D slope_height_texture;
uniform sampler2D slope_ao_texture;
uniform float slope_threshold = 0.7;
uniform float slope_smoothness = 0.2;
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
uniform float specular_aa_strength : hint_range(0.0, 4.0) = 1.0;

varying vec3 world_pos;
varying float height;
varying float v_fragment_ao;
varying vec3 v_planet_up_view;
varying float v_surface_radius;

varying vec3 v_normal_model;
varying vec3 v_vertex_pos_model;
varying float v_caustics;

void vertex() {
	VERTEX = get_transvoxel_position(VERTEX, CUSTOM0, u_transition_mask);
	v_vertex_pos_model = VERTEX;
	v_normal_model = NORMAL;

	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	height = length(world_pos - center) - radius;
}

void fragment() {
    // 1) Normal del voxel suavizada por Transvoxel (la base correcta)
    vec3 normal_model;
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

            TriplanarUVs uvs = compute_triplanar_uvs(planet_pos, texture_scale);
            if (use_parallax) {
                uvs = compute_parallax_uvs_limited(
                    height_textures[tex_index], planet_pos, normal_world, view_world,
                    texture_scale, effective_height,
                    parallax_height_center, parallax_height_contrast, parallax_min_view_dot
                );
            }

            if (height_blend_strength > 0.0001) {
                float material_height = triplanar_scalar_sample_uvs(height_textures[tex_index], uvs, normal_world);
                float height_bias = mix(0.35, 1.35, pow(clamp(material_height, 0.0, 1.0), height_blend_contrast));
                factor *= mix(1.0, height_bias, height_blend_strength);
            }

            vec3 c = triplanar_sample_uvs(textures[tex_index], uvs, normal_world);
            vec4 n_v = triplanar_normal_sample_uvs_v(normal_textures[tex_index], uvs, normal_world);
			
            float r = triplanar_scalar_sample_uvs(roughness_textures[tex_index], uvs, normal_world);
            float ao = triplanar_scalar_sample_uvs(ao_textures[tex_index], uvs, normal_world);

            final_color     += c * factor;
            final_normal    += n_v.xyz * factor;
			final_tightness += n_v.w   * factor;
            final_roughness += r * factor;
            final_ao        += ao * factor;
            total_factor    += factor;
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

    // 7) Salidas
    ALBEDO = final_color;
	NORMAL = normalize((VIEW_MATRIX * vec4(safe_normalize(final_normal, normal_world), 0.0)).xyz);
    ROUGHNESS = final_roughness;
    v_fragment_ao = mix(clamp(final_ao, 0.0, 1.0), 1.0, underwater);
    AO = v_fragment_ao;
    AO_LIGHT_AFFECT = 0.0;
    METALLIC = 0.0;
}

void light()
{
    float distance_to_center = length(world_pos - center);

    float water_light_factor = 1.0;
    if (has_water != 0 && distance_to_center < water_radius) {
        float min_distance = water_radius - water_light_depth;
        water_light_factor = smoothstep(min_distance, water_radius, distance_to_center);
    }

    vec3 n = normalize(NORMAL);
    vec3 l = normalize(LIGHT);
    vec3 v = normalize(VIEW);
    float ndotl = clamp(dot(n, l), 0.0, 1.0);

    float ao = clamp(v_fragment_ao, 0.0, 1.0);
    float direct_ao = mix(1.0, ao, direct_ao_strength);
    float specular_ao = mix(1.0, ao, specular_ao_strength);
    float radius_ratio = clamp(radius / max(v_surface_radius, radius + 0.001), 0.0, 1.0);
    float horizon_cos = -sqrt(max(0.0, 1.0 - radius_ratio * radius_ratio));
    float light_horizon_cos = dot(normalize(v_planet_up_view), l);
    float planet_shadow = smoothstep(
        horizon_cos - planet_shadow_softness,
        horizon_cos + planet_shadow_softness,
        light_horizon_cos
    );

    float light_visibility = ATTENUATION * water_light_factor * planet_shadow;

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
