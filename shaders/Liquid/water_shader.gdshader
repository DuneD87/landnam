shader_type spatial;
render_mode blend_mix, shadows_disabled, depth_prepass_alpha;

uniform sampler2D DEPTH_TEXTURE: hint_depth_texture, filter_linear_mipmap;
uniform sampler2D SCREEN_TEXTURE: hint_screen_texture, filter_linear_mipmap;
uniform vec3 albedo : source_color = vec3(0.05, 0.20, 0.30);
uniform vec3 albedo2 : source_color = vec3(0.10, 0.35, 0.50);
uniform float metallic : hint_range(0.0, 1.0, 0.1) = 0.0;
uniform float roughness : hint_range(0.0, 1.0, 0.1) = 0.05;

uniform sampler2D texture_normal;
uniform sampler2D texture_normal2;
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

uniform float edge_fade_distance : hint_range(0.001, 100.0) = 0.5;
uniform float edge_max_alpha : hint_range(0.0, 1.0) = 0.85;
uniform float edge_min_alpha : hint_range(0.0, 1.0) = 0.15;

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

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec3 sphere_dir = normalize(world_pos - planet_center);
    vec2 uv_coords = vec2(
        atan(sphere_dir.x, sphere_dir.z),
        asin(sphere_dir.y)
    ) * noise_scale;
    height = texture(wave, uv_coords / noise_scale + water_time * time_scale).r;

    float procedural_height = generate_wave(uv_coords, water_time);
    float total_height = height + procedural_height;
    VERTEX += NORMAL * total_height * height_scale;
    world_normal_radial = sphere_dir;

    vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
    view_depth = -view_pos.z - 0.5;
}

void fragment() {
    float depth_texture = texture(DEPTH_TEXTURE, SCREEN_UV).r * 2.0 - 1.0;
    float depth = PROJECTION_MATRIX[3][2] / (depth_texture + PROJECTION_MATRIX[2][2]);

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
    float edge_visibility = 1.0 - smoothstep(10.0, 400.0, view_depth);

    vec2 time = (TIME * wave_direction) * time_scale;
    vec2 time2 = (TIME * wave_direction2) * time_scale;
    vec3 tri_pos = world_pos - planet_center;

    vec3 blend_weights = abs(world_normal_radial);
    blend_weights = pow(blend_weights, vec3(4.0));
    blend_weights /= (blend_weights.x + blend_weights.y + blend_weights.z);

    vec3 n1 = triplanar_normal_udn(texture_normal,  tri_pos, world_normal_radial, blend_weights, normal_scale1, time);
    vec3 n2 = triplanar_normal_udn(texture_normal2, tri_pos, world_normal_radial, blend_weights, normal_scale2, time2 * 0.8);
    vec3 n3 = triplanar_normal_udn(texture_normal,  tri_pos, world_normal_radial, blend_weights, normal_scale3, time * 1.3);

    vec3 final_world_normal = normalize(mix(mix(n1, n2, 0.5), n3, 0.3));
    final_world_normal = normalize(
        mix(world_normal_radial, final_world_normal, clamp(normal_intensity, 0.0, 1.0))
    );

    float normal_edge_factor = smoothstep(0.0, edge_scale * 3.0, z_dif);
    final_world_normal = normalize(
        mix(world_normal_radial, final_world_normal, normal_edge_factor)
    );

    // Refracción
    vec3 tangent_deviation = final_world_normal - world_normal_radial;
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

    vec3 transmission = exp(-absorption_coefficients * water_column);

    float scatter_t = 1.0 - exp(-water_column * 0.18);
    vec3 water_scatter = mix(color_shallow.rgb, color_deep.rgb, scatter_t);

    float visibility = max(max(transmission.r, transmission.g), transmission.b);
    vec3 refracted_light = screen_color * transmission;
    vec3 color = mix(water_scatter, refracted_light, visibility);

    float far_factor = smoothstep(view_opacity_start, view_opacity_end, view_depth);
    color = mix(color, color_deep.rgb, far_factor);

    // Superficie y borde
    float fresnel_value = fresnel(sky_fresnel_power, NORMAL, VIEW);
    vec3 surface_color = mix(albedo, albedo2, fresnel_value);

    float animated_edge = edge_scale * (1.0 + height * 0.5);
    float fade_factor = 1.0 - smoothstep(0.0, animated_edge * 2.0, z_dif);
    fade_factor *= edge_visibility;
    vec3 blended_edge_color = mix(color, edge_color, fade_factor);
    float foam_on_edge = clamp(fade_factor * 1.5, 0.0, 1.0);
    blended_edge_color = mix(blended_edge_color, foam_color, foam_on_edge);

    // Reflexión de cielo
    vec3 reflected_view = reflect(-VIEW, NORMAL);
    vec3 sky_color = calculate_sky_color(reflected_view);
    vec3 sky_reflection = sky_color * sky_influence;

    vec3 final_albedo = mix(blended_edge_color, sky_reflection, fresnel_value * 0.8);
    final_albedo = mix(final_albedo, blended_edge_color, adjusted_depth_blend * 0.3);
    final_albedo = mix(final_albedo, sky_reflection, fresnel_value * sky_influence);
    final_albedo += surface_color * fresnel_value * 0.15;

    // Subsurface scattering
    vec3 sun_dir_norm = normalize(-sun_direction);
    float sss_dot = pow(clamp(dot(VIEW, -sun_dir_norm), 0.0, 1.0), sss_power);
    float sss_depth_mask = clamp(1.0 - adjusted_depth_blend, 0.0, 1.0);
    vec3 sss_contrib = sss_color * sss_dot * sss_intensity * sss_depth_mask * visibility;
    final_albedo += sss_contrib;

    // Glint solar
    vec3 view_dir_world = normalize(world_pos - CAMERA_POSITION_WORLD);
    vec3 to_sun = normalize(-sun_direction);
    vec3 reflect_sun = reflect(-to_sun, NORMAL);
    float glint = pow(max(dot(reflect_sun, -view_dir_world), 0.0), 128.0);
    final_albedo += glint * 2.0 * visibility;

    ALBEDO = clamp(final_albedo, vec3(0.0), vec3(1.0));

    // Alpha
    float distance_alpha = clamp(view_depth / view_opacity_end, 0.0, 1.0);
    distance_alpha = pow(distance_alpha, view_opacity_power);
    float base_alpha = mix(edge_min_alpha, edge_max_alpha, distance_alpha);
    float edge_factor = clamp(z_dif / edge_fade_distance, 0.0, 1.0);
    ALPHA = base_alpha * edge_factor;

    SPECULAR = 0.5;
    METALLIC = metallic;
    ROUGHNESS = roughness;
    NORMAL = normalize((VIEW_MATRIX * vec4(final_world_normal, 0.0)).xyz);
}