shader_type spatial;
render_mode blend_mix, shadows_disabled, depth_draw_always;

uniform sampler2D DEPTH_TEXTURE: hint_depth_texture, filter_linear_mipmap;
uniform sampler2D SCREEN_TEXTURE: hint_screen_texture, filter_linear_mipmap;
uniform vec3 albedo : source_color = vec3(0.05, 0.20, 0.30);
uniform vec3 albedo2 : source_color = vec3(0.10, 0.35, 0.50);
uniform float metallic : hint_range(0.0, 1.0, 0.1) = 0.0;
uniform float roughness : hint_range(0.0, 1.0, 0.1) = 0.05;

uniform sampler2D texture_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D texture_normal2 : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D wave : repeat_enable, filter_linear_mipmap;

uniform vec2 wave_direction = vec2(2.0, 0.0);
uniform vec2 wave_direction2 = vec2(0.0, 1.0);
uniform float time_scale : hint_range(0.0, 0.2, 0.001) = 0.025;
uniform float noise_scale = 8.0;
uniform float height_scale = 0.35;

// Parámetros para romper el tiling de las normales
uniform float normal_scale1 : hint_range(0.1, 500.0) = 4.0;
uniform float normal_scale2 : hint_range(0.1, 500.0) = 12.0;
uniform float normal_scale3 : hint_range(0.1, 500.0) = 35.0;
uniform float normal_intensity : hint_range(0.0, 200.0) = 0.7;
uniform float wave_normal_sample_distance : hint_range(0.01, 100.0, 0.01) = 2.0;

uniform float wave_speed = 0.7;
uniform float wave_amplitude = 0.6;
uniform float wave_frequency = 0.8;

uniform vec4 color_deep : source_color = vec4(0.02, 0.14, 0.25, 1.0);
uniform vec4 color_shallow : source_color = vec4(0.37, 0.72, 0.71, 1.0);
uniform float beers_law = 1.5;
uniform float depth_offset = 0.0;

// Coeficientes de absorción Beer-Lambert por canal RGB.
uniform vec3 absorption_coefficients = vec3(0.45, 0.18, 0.06);

uniform float edge_scale = 0.15;
uniform float near = 1.0;
uniform float far = 100.0;
uniform vec3 edge_color : source_color = vec3(0.7, 0.85, 0.95);
uniform float edge_disable_start : hint_range(0.0, 1000.0) = 60.0;
uniform float edge_disable_end : hint_range(0.0, 1000.0) = 150.0;
uniform float detail_fade_start : hint_range(0.0, 2000.0) = 80.0;
uniform float detail_fade_end : hint_range(0.0, 2000.0) = 250.0;
uniform vec3 distant_water_color : source_color = vec3(0.08, 0.22, 0.35);
uniform float edge_fade_distance : hint_range(0.001, 100.0) = 0.5;
uniform float edge_max_alpha : hint_range(0.0, 1.0) = 0.85;
uniform float edge_min_alpha : hint_range(0.0, 1.0) = 0.15;
uniform float foam_edge_width : hint_range(0.01, 1.0) = 0.35;
uniform float surface_alpha : hint_range(0.0, 1.0) = 0.15;
uniform float deep_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float foam_alpha_boost : hint_range(0.0, 1.0) = 0.18;
uniform float depth_alpha_start : hint_range(0.0, 1000.0) = 0.0;
uniform float depth_alpha_end : hint_range(0.001, 10000.0) = 40.0;
uniform float depth_alpha_power : hint_range(0.01, 10.0) = 1.4;

uniform float view_opacity_start : hint_range(0.0, 50.0) = 8.0;
uniform float view_opacity_end : hint_range(-10000.0, 10000.0) = 60.0;
uniform float view_opacity_power : hint_range(0.01, 50.0) = 1.5;

uniform vec3 sky_color_horizon : source_color = vec3(0.75, 0.85, 0.95);
uniform vec3 sky_color_zenith : source_color = vec3(0.30, 0.55, 0.85);
uniform float sky_influence : hint_range(0.0, 20.0) = 0.6;
uniform float sky_fresnel_power : hint_range(0.1, 100.0) = 5.0;
uniform float sky_gradient_power : hint_range(0.1, 50.0) = 2.5;

uniform vec3 sun_direction = vec3(0.4, -0.7, 0.3);

uniform vec3 sss_color : source_color = vec3(0.15, 0.55, 0.45);
uniform float sss_intensity : hint_range(0.0, 3.0) = 0.8;
uniform float sss_power : hint_range(1.0, 8.0) = 4.0;

uniform vec3 foam_color : source_color = vec3(0.92, 0.96, 0.98);

uniform float water_time;
uniform vec3 planet_center;
uniform float water_radius;

varying vec3 world_pos;
varying vec3 base_world_pos;
varying float height;
varying float view_depth;
varying vec3 world_normal_radial;

float fresnel(float amount, vec3 normal, vec3 view) {
    return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0)), amount);
}

float edge(float depth){
    depth = 1.0 - 2.0 * depth;
    return near * far / (far + depth * (near - far));
}

// Olas procedurales como fallback / complemento
float generate_wave(vec2 pos, float time) {
    float wave1 = sin(pos.x * wave_frequency + time * wave_speed) * wave_amplitude;
    float wave2 = sin(pos.y * wave_frequency * 0.7 + time * wave_speed * 0.8) * wave_amplitude * 0.5;
    float wave3 = sin((pos.x + pos.y) * wave_frequency * 0.5 + time * wave_speed * 1.2) * wave_amplitude * 0.3;
    return (wave1 + wave2 + wave3) * 0.1;
}

vec2 water_sphere_uv(vec3 sample_world_pos) {
    vec3 sphere_dir = normalize(sample_world_pos - planet_center);
    return vec2(
        atan(sphere_dir.x, sphere_dir.z),
        asin(sphere_dir.y)
    ) * noise_scale;
}

float sample_water_height(vec3 sample_world_pos, float time_value) {
    vec2 uv_coords = water_sphere_uv(sample_world_pos);
    float wave_height = texture(wave, uv_coords / noise_scale + time_value * time_scale).r;
    float procedural_height = generate_wave(uv_coords, time_value);
    return (wave_height + procedural_height) * height_scale;
}

vec3 calculate_wave_world_normal(vec3 sample_world_pos, vec3 radial_normal, float time_value) {
    vec3 tangent_seed = abs(radial_normal.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(tangent_seed, radial_normal));
    vec3 bitangent = normalize(cross(radial_normal, tangent));
    float eps = wave_normal_sample_distance;

    vec3 p0 = sample_world_pos + radial_normal * sample_water_height(sample_world_pos, time_value);

    vec3 tangent_base = sample_world_pos + tangent * eps;
    vec3 bitangent_base = sample_world_pos + bitangent * eps;
    vec3 tangent_radial = normalize(tangent_base - planet_center);
    vec3 bitangent_radial = normalize(bitangent_base - planet_center);

    vec3 p_tangent = tangent_base + tangent_radial * sample_water_height(tangent_base, time_value);
    vec3 p_bitangent = bitangent_base + bitangent_radial * sample_water_height(bitangent_base, time_value);

    vec3 wave_normal = normalize(cross(p_bitangent - p0, p_tangent - p0));
    if (dot(wave_normal, radial_normal) < 0.0) {
        wave_normal = -wave_normal;
    }
    return wave_normal;
}

vec3 calculate_sky_color(vec3 view_direction) {
    float vertical_angle = clamp(view_direction.y * 0.5 + 0.5, 0.0, 1.0);
    vertical_angle = pow(vertical_angle, sky_gradient_power);
    return mix(sky_color_horizon, sky_color_zenith, vertical_angle);
}

// Triplanar con UDN blend — devuelve normal en WORLD SPACE
vec3 triplanar_normal_udn(sampler2D tex, vec3 pos, vec3 surface_normal,
                          vec3 weights, float scale, vec2 time_offset) {
    vec3 n_xz = texture(tex, pos.xz / scale + time_offset).rgb * 2.0 - 1.0;
    vec3 n_xy = texture(tex, pos.xy / scale + time_offset).rgb * 2.0 - 1.0;
    vec3 n_yz = texture(tex, pos.yz / scale + time_offset).rgb * 2.0 - 1.0;

    vec3 world_n_xz = vec3(n_xz.x, 0.0, n_xz.y);
    vec3 world_n_xy = vec3(n_xy.x, n_xy.y, 0.0);
    vec3 world_n_yz = vec3(0.0, n_yz.y, n_yz.x);

    vec3 blended = world_n_xz * weights.y
                 + world_n_xy * weights.z
                 + world_n_yz * weights.x;

    return normalize(blended + surface_normal);
}

float linearize_depth(float depth_sample, mat4 projection_matrix) {
    float ndc = depth_sample * 2.0 - 1.0;
    return projection_matrix[3][2] / (ndc + projection_matrix[2][2]);
}

vec3 reconstruct_world_position(vec2 uv, float depth_sample, mat4 inv_projection_matrix, mat4 inv_view_matrix) {
    vec3 ndc;
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
        ndc = vec3(uv, depth_sample) * 2.0 - 1.0;
    #else
        ndc = vec3(uv * 2.0 - 1.0, depth_sample);
    #endif

    vec4 world = inv_view_matrix * inv_projection_matrix * vec4(ndc, 1.0);
    return world.xyz / world.w;
}

float ray_sphere_depth(vec3 ray_origin, vec3 ray_direction, vec3 sphere_center, float sphere_radius) {
    if (sphere_radius <= 0.0) {
        return 0.0;
    }

    vec3 offset = ray_origin - sphere_center;
    float b = dot(offset, ray_direction);
    float c = dot(offset, offset) - sphere_radius * sphere_radius;
    float discriminant = b * b - c;

    if (discriminant <= 0.0) {
        return 0.0;
    }

    float root = sqrt(discriminant);
    float enter_distance = max(-b - root, 0.0);
    float exit_distance = max(-b + root, 0.0);
    return max(exit_distance - enter_distance, 0.0);
}

void vertex() {
    base_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec3 sphere_dir = normalize(base_world_pos - planet_center);
    vec2 uv_coords = water_sphere_uv(base_world_pos);
    height = texture(wave, uv_coords / noise_scale + water_time * time_scale).r;

    float total_height = sample_water_height(base_world_pos, water_time);
    VERTEX += NORMAL * total_height;
    world_normal_radial = sphere_dir;
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

    vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
    view_depth = -view_pos.z - 0.5;
}

void fragment() {
    float depth_texture = texture(DEPTH_TEXTURE, SCREEN_UV).r * 2.0 - 1.0;
    float depth = PROJECTION_MATRIX[3][2] / (depth_texture + PROJECTION_MATRIX[2][2]);
	float detail_fade = smoothstep(detail_fade_start, detail_fade_end, view_depth);
    float water_depth = depth + VERTEX.z + depth_offset;
    float depth_blend = exp(water_depth * -beers_law);
    depth_blend = clamp(1.0 - depth_blend, 0.0, 1.0);
    float depth_blend_power = clamp(pow(depth_blend, 2.5), 0.0, 1.0);

    float view_distance_factor = clamp(
        (view_depth - view_opacity_start) / (view_opacity_end - view_opacity_start),
        0.0,
        1.0
    );
    view_distance_factor = pow(view_distance_factor, view_opacity_power);

    float adjusted_depth_blend = mix(depth_blend_power, 1.0, view_distance_factor);

    float z_depth = edge(texture(DEPTH_TEXTURE, SCREEN_UV).x);
	float z_pos = edge(FRAGCOORD.z);
	float z_dif = z_depth - z_pos;

	// 0 cerca (edges activos), 1 lejos (edges desactivados)
	float edge_disable = smoothstep(edge_disable_start, edge_disable_end, view_depth);
	float edge_visibility = 1.0 - edge_disable; // sustituye al smoothstep(10,400,...)

    vec3 radial_normal = normalize(world_normal_radial);
    vec3 wave_world_normal = calculate_wave_world_normal(base_world_pos, radial_normal, water_time);
    vec3 final_world_normal = wave_world_normal;

	if (detail_fade < 0.999) {
	    vec2 time  = (TIME * wave_direction)  * time_scale;
	    vec2 time2 = (TIME * wave_direction2) * time_scale;
	    vec3 tri_pos = world_pos - planet_center;

	    vec3 blend_weights = abs(wave_world_normal);
	    blend_weights = pow(blend_weights, vec3(4.0));
	    blend_weights /= (blend_weights.x + blend_weights.y + blend_weights.z);

	    vec3 n1 = triplanar_normal_udn(texture_normal,  tri_pos, wave_world_normal, blend_weights, normal_scale1, time);
	    vec3 n2 = triplanar_normal_udn(texture_normal2, tri_pos, wave_world_normal, blend_weights, normal_scale2, time2 * 0.8);
	    vec3 n3 = triplanar_normal_udn(texture_normal,  tri_pos, wave_world_normal, blend_weights, normal_scale3, time * 1.3);

	    vec3 detailed_normal = normalize(mix(mix(n1, n2, 0.5), n3, 0.3));
	    detailed_normal = normalize(
	        mix(wave_world_normal, detailed_normal, clamp(normal_intensity, 0.0, 100.0))
	    );

	    // Fade hacia normal radial lisa con la distancia
	    final_world_normal = normalize(mix(detailed_normal, wave_world_normal, detail_fade));
	}

    float normal_edge_factor = smoothstep(0.0, edge_scale * 3.0, z_dif);
	normal_edge_factor = mix(normal_edge_factor, 1.0, edge_disable);
	final_world_normal = normalize(mix(radial_normal, final_world_normal, normal_edge_factor));

    // Refracción
    vec3 tangent_deviation = final_world_normal - radial_normal;
    vec3 enhanced_deviation = tangent_deviation * 5.0;
    vec3 tangent_dev_view = (VIEW_MATRIX * vec4(enhanced_deviation, 0.0)).xyz;

    float strength = 0.05;
    float screen_influence = 1.0;
    float depth_fac = 1.0;

    vec2 refraction_offset = tangent_dev_view.xy * strength * screen_influence * depth_fac;
    refraction_offset += vec2(sin(world_pos.z * 5.0 + TIME), cos(world_pos.x * 5.0 + TIME)) * 0.002;

    vec2 refracted_uv = SCREEN_UV + refraction_offset;

    float frag_linear = linearize_depth(FRAGCOORD.z, PROJECTION_MATRIX);
    float refr_linear = linearize_depth(texture(DEPTH_TEXTURE, refracted_uv).r, PROJECTION_MATRIX);
    vec2 final_uv = (refr_linear < frag_linear) ? SCREEN_UV : refracted_uv;

    vec3 screen_color = textureLod(SCREEN_TEXTURE, final_uv, adjusted_depth_blend * 2.5).rgb;

    // Absorción Beer-Lambert con corrección por ángulo
    float scene_linear = linearize_depth(texture(DEPTH_TEXTURE, final_uv).r, PROJECTION_MATRIX);
    float depth_diff = max(scene_linear - frag_linear, 0.0);

    vec3 view_dir_w = normalize(world_pos - CAMERA_POSITION_WORLD);
    vec3 cam_fwd    = -normalize((INV_VIEW_MATRIX * vec4(0.0, 0.0, -1.0, 0.0)).xyz);
    float cos_view  = max(abs(dot(view_dir_w, cam_fwd)), 0.15);
    float water_column = depth_diff / cos_view;
    float scene_depth_sample = texture(DEPTH_TEXTURE, SCREEN_UV).r;
    vec3 scene_world_pos = reconstruct_world_position(SCREEN_UV, scene_depth_sample, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
    float terrain_water_depth = max(water_radius - length(scene_world_pos - planet_center), 0.0);
    float sphere_water_depth = ray_sphere_depth(CAMERA_POSITION_WORLD, view_dir_w, planet_center, water_radius);
    float measured_water_depth = max(terrain_water_depth, water_column);
    float has_scene_depth = 1.0 - step(0.9999, scene_depth_sample);
    float use_sphere_fallback = (1.0 - has_scene_depth) * (1.0 - step(0.001, measured_water_depth));
    float opacity_depth = mix(measured_water_depth, sphere_water_depth, use_sphere_fallback);
    float depth_alpha_factor = smoothstep(depth_alpha_start, depth_alpha_end, opacity_depth);
    depth_alpha_factor = pow(depth_alpha_factor, depth_alpha_power);

    vec3 transmission = exp(-absorption_coefficients * opacity_depth);

    float scatter_t = 1.0 - exp(-opacity_depth * 0.18);
    vec3 water_scatter = mix(color_shallow.rgb, color_deep.rgb, scatter_t);

    float visibility = max(max(transmission.r, transmission.g), transmission.b) * (1.0 - depth_alpha_factor);
    vec3 refracted_light = screen_color * transmission;
    vec3 color = mix(water_scatter, refracted_light, visibility);

    float far_factor = smoothstep(view_opacity_start, view_opacity_end, view_depth);
    color = mix(color, color_deep.rgb, far_factor);
	vec3 view_normal = normalize((VIEW_MATRIX * vec4(final_world_normal, 0.0)).xyz);
	NORMAL = view_normal;
    // Superficie y borde
	float fresnel_value = fresnel(sky_fresnel_power, view_normal, VIEW);
    vec3 surface_color = mix(albedo, albedo2, fresnel_value);

    float animated_edge = edge_scale * (1.0 + height * 0.5);
    float fade_factor = 1.0 - smoothstep(0.0, animated_edge * 2.0, z_dif);
	fade_factor *= edge_visibility;
    vec3 blended_edge_color = mix(color, edge_color, fade_factor);
    float foam_on_edge = smoothstep(1.0 - foam_edge_width, 1.0, fade_factor);
    blended_edge_color = mix(blended_edge_color, foam_color, foam_on_edge);

    // Reflexión de cielo
	vec3 reflected_view = reflect(-VIEW, view_normal);
    vec3 sky_color = calculate_sky_color(reflected_view);
    vec3 sky_reflection = sky_color * sky_influence;

    vec3 final_albedo = mix(blended_edge_color, sky_reflection, fresnel_value * 0.8);
    final_albedo = mix(final_albedo, blended_edge_color, adjusted_depth_blend * 0.3);
    final_albedo = mix(final_albedo, sky_reflection, fresnel_value * sky_influence);
    final_albedo += surface_color * fresnel_value * 0.15;
    final_albedo = mix(final_albedo, color_deep.rgb, depth_alpha_factor * 0.65);

    // Subsurface scattering
    vec3 safe_sun_direction = sun_direction;
    if (dot(safe_sun_direction, safe_sun_direction) < 0.0001) {
        safe_sun_direction = vec3(0.4, -0.7, 0.3);
    }
    vec3 sun_dir_norm = normalize(-safe_sun_direction);
    float sss_dot = pow(clamp(dot(VIEW, -sun_dir_norm), 0.0, 1.0), sss_power);
    float sss_depth_mask = clamp(1.0 - adjusted_depth_blend, 0.0, 1.0);
    vec3 sss_contrib = sss_color * sss_dot * sss_intensity * sss_depth_mask * visibility;
    final_albedo += sss_contrib;

    ALBEDO = clamp(final_albedo, vec3(0.0), vec3(1.0));

    // Alpha by terrain depth: shallow seabed stays transparent, deep water becomes opaque.
    float base_alpha = mix(surface_alpha, deep_alpha, depth_alpha_factor);
    ALPHA = clamp(base_alpha + foam_on_edge * foam_alpha_boost * (1.0 - base_alpha), 0.0, deep_alpha);

    SPECULAR = 0.5;
    METALLIC = metallic;
    ROUGHNESS = roughness;


}
