shader_type spatial;
render_mode blend_mix, shadows_disabled, depth_draw_always;

uniform bool debug_wireframe = true;
uniform float wireframe_thickness : hint_range(0.5, 5.0) = 1.5;
uniform vec3 wireframe_color : source_color = vec3(0.0, 1.0, 0.4);
uniform vec3 wireframe_bg : source_color = vec3(0.05, 0.05, 0.1);

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
uniform float time_scale : hint_range(0.0, 0.2, 0.001) = 0.0025;
uniform float noise_scale = 8.0;
uniform float height_scale = 0.35;

// Parámetros para romper el tiling de las normales
uniform float normal_scale1 : hint_range(0.1, 500.0) = 40.0;
uniform float normal_scale2 : hint_range(0.1, 500.0) = 120.0;
uniform float normal_scale3 : hint_range(0.1, 500.0) = 350.0;
uniform float normal_intensity : hint_range(0.0, 200.0) = 7.0;
uniform float wave_normal_sample_distance : hint_range(0.01, 100.0, 0.01) = 2.0;

uniform float wave_speed = 1.5;
uniform float wave_amplitude = 4.0;
uniform float wave_frequency = 2.0;
uniform float wave_world_scale : hint_range(1.0, 500.0) = 60.0; // metros por tile

uniform vec4 color_deep : source_color = vec4(0.02, 0.14, 0.25, 1.0);
uniform vec4 color_shallow : source_color = vec4(0.37, 0.72, 0.71, 1.0);
uniform float beers_law = 1.5;
uniform float depth_offset = 0.0;

// Coeficientes de absorción Beer-Lambert por canal RGB.
uniform vec3 absorption_coefficients = vec3(0.45, 0.18, 0.06);

uniform float edge_scale = 10.0;
uniform float edge_disable_start : hint_range(0.0, 1000.0) = 60.0;
uniform float edge_disable_end : hint_range(0.0, 1000.0) = 150.0;
uniform float detail_fade_start : hint_range(0.0, 2000.0) = 80.0;
uniform float detail_fade_end : hint_range(0.0, 2000.0) = 250.0;

uniform float surface_alpha : hint_range(0.0, 1.0) = 0.15;
uniform float deep_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float refraction_alpha_floor : hint_range(0.0, 1.0) = 0.32;
uniform float refraction_strength : hint_range(0.0, 2.0, 0.001) = 0.05;
uniform float refraction_depth_fade : hint_range(0.01, 100.0, 0.01) = 8.0;
uniform float refraction_uv_margin : hint_range(0.0, 0.05, 0.001) = 0.002;
uniform float depth_alpha_start : hint_range(0.0, 1000.0) = 0.0;
uniform float depth_alpha_end : hint_range(0.001, 10000.0) = 40.0;
uniform float depth_alpha_power : hint_range(0.01, 10.0) = 1.4;

uniform vec3 sky_color_horizon : source_color = vec3(0.75, 0.85, 0.95);
uniform vec3 sky_color_zenith : source_color = vec3(0.30, 0.55, 0.85);
uniform float sky_influence : hint_range(0.0, 20.0) = 0.6;
uniform float sky_fresnel_power : hint_range(0.1, 100.0) = 5.0;
uniform float sky_gradient_power : hint_range(0.1, 50.0) = 2.5;

uniform vec3 sun_direction = vec3(0.4, -0.7, 0.3);

uniform vec3 sss_color : source_color = vec3(0.15, 0.55, 0.45);
uniform float sss_intensity : hint_range(0.0, 3.0) = 0.8;
uniform float sss_power : hint_range(1.0, 8.0) = 4.0;

// Espuma procedural
uniform vec3 foam_color : source_color = vec3(0.92, 0.96, 0.98);
uniform float foam_depth_start : hint_range(0.0, 5.0, 0.01) = 0.8;
uniform float foam_depth_end   : hint_range(0.0, 5.0, 0.01) = 0.0;
uniform float foam_noise_scale : hint_range(0.0, 10.0, 0.01) = 2.0;
uniform float foam_noise_speed : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float foam_cutoff      : hint_range(0.0, 1.0, 0.01) = 0.7;
uniform float foam_crest_threshold : hint_range(0.0, 1.0, 0.01) = 0.7;
uniform float foam_crest_amount    : hint_range(0.0, 10.0, 0.1) = 2.0;
uniform vec3 foam_edge_color : source_color = vec3(0.0, 0.0, 0.05);
uniform vec2 foam_edge_offset = vec2(0.02, 0.02);
uniform float voronoi_scale   : hint_range(0.0, 50.0) = 9.0;
uniform float voronoi_strength : hint_range(0.0, 8.0) = 0.8;
uniform float shore_soft_width : hint_range(0.01, 10.0, 0.01) = 1.5;

// Caustics
uniform sampler2D caustics_texture : filter_linear_mipmap, repeat_enable;
uniform float caustics_scale : hint_range(0.1, 10.0, 0.1) = 2.0;
uniform float caustics_speed : hint_range(0.0, 1.0, 0.01) = 0.1;
uniform float caustics_intensity : hint_range(0.0, 2.0, 0.1) = 0.8;
uniform float caustics_depth_fade : hint_range(0.0, 1.0, 0.01) = 0.7;
uniform float caustics_near_fade : hint_range(0.0, 10.0, 0.1) = 1.5;

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

float generate_wave_world(vec3 wpos, vec3 radial, float t) {
    vec3 seed = abs(radial.y) < 0.99 ? vec3(0,1,0) : vec3(1,0,0);
    vec3 tan = normalize(cross(seed, radial));
    vec3 bit = normalize(cross(radial, tan));

    vec3 local = wpos - planet_center;
    vec2 p = vec2(dot(local, tan), dot(local, bit));

    float w1 = sin(p.x * wave_frequency + t * wave_speed) * wave_amplitude;
    float w2 = sin(p.y * wave_frequency * 0.7 + t * wave_speed * 0.8) * wave_amplitude * 0.5;
    float w3 = sin((p.x + p.y) * wave_frequency * 0.5 + t * wave_speed * 1.2) * wave_amplitude * 0.3;
    return (w1 + w2 + w3) * 0.1;
}

float sample_water_height(vec3 sample_world_pos, float time_value) {
    vec3 radial = normalize(sample_world_pos - planet_center);
    vec3 tri_pos = sample_world_pos - planet_center;

    vec3 w = abs(radial);
    w = pow(w, vec3(4.0));
    w /= (w.x + w.y + w.z);

    vec2 t = wave_direction * time_value * time_scale;

    float h_xz = texture(wave, tri_pos.xz / wave_world_scale + t).r;
    float h_xy = texture(wave, tri_pos.xy / wave_world_scale + t).r;
    float h_yz = texture(wave, tri_pos.yz / wave_world_scale + t).r;

    float tex_height = h_xz * w.y + h_xy * w.z + h_yz * w.x;
    float procedural = generate_wave_world(sample_world_pos, radial, time_value);

    return (tex_height + procedural) * height_scale;
}

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

/*float sample_water_height(vec3 sample_world_pos, float time_value) {
    vec2 uv_coords = water_sphere_uv(sample_world_pos);
    float wave_height = texture(wave, uv_coords / noise_scale + time_value * time_scale).r;
    float procedural_height = generate_wave(uv_coords, time_value);
    return (wave_height + procedural_height) * height_scale;
}*/

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

float linearize_depth(vec2 uv, float depth_sample, mat4 inv_projection_matrix) {
    vec3 ndc;
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
        ndc = vec3(uv, depth_sample) * 2.0 - 1.0;
    #else
        ndc = vec3(uv * 2.0 - 1.0, depth_sample);
    #endif

    vec4 view = inv_projection_matrix * vec4(ndc, 1.0);
    view.xyz /= view.w;
    return -view.z;
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

// --- Foam noise helpers ---

float hash13(vec3 p) {
    uvec3 q = uvec3(ivec3(p)) * uvec3(1597334677u, 3812015801u, 2798796415u);
    uint n = (q.x ^ q.y ^ q.z) * 1597334677u;
    return float(n) * (1.0 / 4294967295.0);
}

vec2 hash22(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// Distancia al punto Voronoi más cercano; animado para crear movimiento orgánico
float voronoi_noise(vec2 uv) {
    vec2 n = floor(uv);
    vec2 f = fract(uv);
    float m_dist = 1.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 g = vec2(float(i), float(j));
            vec2 o = hash22(n + g);
            o = 0.5 + 0.5 * sin(TIME * foam_noise_speed + 6.2831 * o);
            vec2 r = g - f + o;
            float d = dot(r, r);
            m_dist = min(m_dist, d);
        }
    }
    return m_dist;
}

float noise3d(in vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(
            mix(hash13(i + vec3(0.0, 0.0, 0.0)), hash13(i + vec3(1.0, 0.0, 0.0)), f.x),
            mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
        mix(
            mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), f.x),
            mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

// fBm sobre Voronoi: acumula capas para crear cúmulos de espuma orgánicos
float fbm_voronoi(vec2 uv) {
    float v = 0.0;
    float a = 0.5;
    vec2 shift = vec2(100.0);
    mat2 rot = mat2(vec2(cos(0.5), sin(0.5)), vec2(-sin(0.5), cos(0.5)));
    for (int i = 0; i < 3; i++) {
        float val = 1.0 - voronoi_noise(uv);
        val = pow(val, 2.0);
        v += a * val;
        uv = rot * uv * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

// ---

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
    float scene_depth_sample = texture(DEPTH_TEXTURE, SCREEN_UV).r;
    float frag_linear = linearize_depth(SCREEN_UV, FRAGCOORD.z, INV_PROJECTION_MATRIX);
    vec3 view_dir_w = normalize(world_pos - CAMERA_POSITION_WORLD);
    vec3 cam_fwd    = -normalize((INV_VIEW_MATRIX * vec4(0.0, 0.0, -1.0, 0.0)).xyz);
    float cos_view  = max(abs(dot(view_dir_w, cam_fwd)), 0.15);
    vec3 scene_world_pos = reconstruct_world_position(SCREEN_UV, scene_depth_sample, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
    float terrain_water_depth = max(water_radius - length(scene_world_pos - planet_center), 0.0);
    float scene_linear_at_screen = linearize_depth(SCREEN_UV, scene_depth_sample, INV_PROJECTION_MATRIX);
    float detail_fade = smoothstep(detail_fade_start, detail_fade_end, view_depth);
    float water_depth = max(scene_linear_at_screen - frag_linear, 0.0) + depth_offset;
    float depth_blend = exp(water_depth * -beers_law);
    depth_blend = clamp(1.0 - depth_blend, 0.0, 1.0);
    float depth_blend_power = clamp(pow(depth_blend, 2.5), 0.0, 1.0);

    float view_distance = length(world_pos - CAMERA_POSITION_WORLD);
    float view_opacity_factor = smoothstep(0.0, edge_disable_end, view_distance);
    float adjusted_depth_blend = mix(depth_blend_power, 1.0, view_opacity_factor);

    float z_depth = linearize_depth(SCREEN_UV, texture(DEPTH_TEXTURE, SCREEN_UV).r, INV_PROJECTION_MATRIX);
    float z_pos   = frag_linear;
    float z_dif   = z_depth - z_pos;

    float edge_disable = smoothstep(edge_disable_start, edge_disable_end, view_depth);

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

    // Nivel de espuma: 1.0 en orilla/crestas, 0.0 en agua profunda
    float depth_foam_factor = smoothstep(foam_depth_start, foam_depth_end, water_depth);
    // Usamos dot con la normal radial para detectar crestas en una esfera planetaria.
    // dot ≈ 1.0 = superficie plana, dot < threshold = cresta de ola.
    float normal_alignment = dot(final_world_normal, radial_normal);
    float wave_crest_factor = smoothstep(foam_crest_threshold, foam_crest_threshold - 0.1, normal_alignment);
    wave_crest_factor *= foam_crest_amount;
    float foam_level = clamp(depth_foam_factor + wave_crest_factor, 0.0, 1.0);

    // Domain warp animado para movimiento de corriente
    vec2 flow_uv = world_pos.xz * 0.5 + TIME * 0.05 * foam_noise_speed;
    vec2 warp = vec2(
        noise3d(vec3(flow_uv, 0.0)),
        noise3d(vec3(flow_uv + vec2(5.2, 1.3), 0.0))
    ) * 0.5;

    // Refracción — suprimida donde aparece espuma
    vec3 tangent_deviation = final_world_normal - radial_normal;
    vec3 enhanced_deviation = tangent_deviation * 5.0;
    vec3 tangent_dev_view = (VIEW_MATRIX * vec4(enhanced_deviation, 0.0)).xyz;

    vec2 probe_offset = tangent_dev_view.xy * refraction_strength * 0.5;
    vec2 probe_uv = clamp(SCREEN_UV + probe_offset,
                          vec2(refraction_uv_margin),
                          vec2(1.0 - refraction_uv_margin));
    float probe_depth_sample = texture(DEPTH_TEXTURE, probe_uv).r;
    float probe_linear = linearize_depth(probe_uv, probe_depth_sample, INV_PROJECTION_MATRIX);
    float depth_at_probe = max(probe_linear - frag_linear, 0.0);

    float depth_fac = clamp(depth_at_probe / refraction_depth_fade, 0.0, 4.0);

    float refraction_angle_factor = smoothstep(0.15, 0.6, cos_view);
    vec4 dev_clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(enhanced_deviation, 0.0);
    vec2 dev_screen = dev_clip.xy / max(frag_linear, 0.001);

    vec2 refraction_offset = dev_screen
                           * refraction_strength
                           * depth_fac
                           * refraction_angle_factor
                           * (1.0 - foam_level); // sin refracción en orillas

    vec2 refracted_uv = clamp(
        SCREEN_UV + refraction_offset,
        vec2(refraction_uv_margin),
        vec2(1.0 - refraction_uv_margin)
    );

    float refracted_depth_sample = texture(DEPTH_TEXTURE, refracted_uv).r;
    float refr_linear = linearize_depth(refracted_uv, refracted_depth_sample, INV_PROJECTION_MATRIX);
    float refracted_is_under_water = step(frag_linear + 0.02, refr_linear);
    vec2 final_uv = mix(SCREEN_UV, refracted_uv, refracted_is_under_water * depth_fac);

    vec3 screen_color = textureLod(SCREEN_TEXTURE, final_uv, adjusted_depth_blend * 2.5).rgb;

    // Cáusticas submarinas
    vec4 bg_ndc = vec4(final_uv * 2.0 - 1.0, texture(DEPTH_TEXTURE, final_uv).x, 1.0);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    bg_ndc.z = bg_ndc.z * 2.0 - 1.0;
#endif
    vec4 bg_world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * bg_ndc;
    vec3 bg_world_pos = bg_world.xyz / bg_world.w;
    float caustics_contrib = 0.0;
    if (water_depth > 0.0) {
        // Coordenadas esféricas del fondo: invariantes al desplazamiento radial de las olas
        // y sin estiramiento en bordes a diferencia de la proyección XZ plana.
        vec3 bg_dir = normalize(bg_world_pos - planet_center);
        // * water_radius convierte radianes a longitud de arco → escala equivalente a XZ en metros
        vec2 bg_sphere_uv = vec2(atan(bg_dir.x, bg_dir.z), asin(bg_dir.y)) * water_radius;
        vec2 caustics_uv1 = bg_sphere_uv * caustics_scale;
        caustics_uv1.x += TIME * caustics_speed;
        vec2 caustics_uv2 = bg_sphere_uv * caustics_scale * 0.7;
        caustics_uv2.y -= TIME * caustics_speed * 0.8;
        float caustics_sample1 = texture(caustics_texture, caustics_uv1).r;
        float caustics_sample2 = texture(caustics_texture, caustics_uv2).r;
        float caustics_value = caustics_sample1 * caustics_sample2;
        float caustics_fade = smoothstep(0.0, caustics_near_fade, water_depth)
                            * (1.0 - clamp(water_depth * caustics_depth_fade, 0.0, 1.0));
        caustics_contrib = caustics_value * caustics_intensity * caustics_fade;
    }

    // Absorción Beer-Lambert con corrección por ángulo
    float scene_linear = linearize_depth(final_uv, texture(DEPTH_TEXTURE, final_uv).r, INV_PROJECTION_MATRIX);
    float depth_diff = max(scene_linear - frag_linear, 0.0);
    float water_column = depth_diff / cos_view;

    float sphere_water_depth = ray_sphere_depth(CAMERA_POSITION_WORLD, view_dir_w, planet_center, water_radius);
    float measured_water_depth = max(terrain_water_depth, water_column);
    float has_scene_depth = 1.0 - step(0.9999, scene_depth_sample);
    float use_sphere_fallback = (1.0 - has_scene_depth) * (1.0 - step(0.001, measured_water_depth));
    float opacity_depth = mix(measured_water_depth, sphere_water_depth, use_sphere_fallback);
    float depth_alpha_factor = smoothstep(depth_alpha_start, depth_alpha_end, opacity_depth);
    depth_alpha_factor = pow(depth_alpha_factor, depth_alpha_power);
    float grazing = 1.0 - clamp(dot(radial_normal, -view_dir_w), 0.0, 1.0);
    float grazing_opacity = smoothstep(0.65, 0.95, grazing);
    float opacity_factor = max(max(depth_alpha_factor, view_opacity_factor), grazing_opacity);

    vec3 transmission = exp(-absorption_coefficients * opacity_depth);

    float scatter_t = 1.0 - exp(-opacity_depth * 0.08);
    vec3 water_scatter = mix(color_shallow.rgb, color_deep.rgb, scatter_t);

    float visibility = max(max(transmission.r, transmission.g), transmission.b) * (1.0 - opacity_factor);
    vec3 refracted_light = screen_color * transmission;
    vec3 color = mix(water_scatter, refracted_light, visibility);
    color = mix(color, color_deep.rgb, view_opacity_factor);

    vec3 view_normal = normalize((VIEW_MATRIX * vec4(final_world_normal, 0.0)).xyz);
    NORMAL = view_normal;

    float fresnel_value = fresnel(sky_fresnel_power, view_normal, VIEW);
    vec3 surface_color = mix(albedo, albedo2, fresnel_value);

    vec3 reflected_view = reflect(-VIEW, view_normal);
    vec3 sky_color = calculate_sky_color(reflected_view);
    vec3 sky_reflection = sky_color * sky_influence;

    vec3 final_albedo = mix(color, sky_reflection, fresnel_value * 0.8);
    final_albedo = mix(final_albedo, color, adjusted_depth_blend * 0.3);
    final_albedo = mix(final_albedo, sky_reflection, fresnel_value * sky_influence);
    final_albedo += surface_color * fresnel_value * 0.15;
    final_albedo = mix(final_albedo, color_deep.rgb, opacity_factor);

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

    // Espuma procedural Voronoi
    float foam_mask_primary = 0.0;
    float foam_mask_shadow  = 0.0;

    if (water_depth > 0.01) {
        vec2 foam_uv = world_pos.xz * foam_noise_scale + warp;

        // Control de emergencia: la espuma no aparece en todos lados a la vez
        float emergence_noise = noise3d(vec3(world_pos.xz * 0.5, TIME * 0.2 * foam_noise_speed));
        emergence_noise = smoothstep(0.0, 1.0, emergence_noise * 0.5 + 0.5);
        float effective_emergence = mix(emergence_noise, 1.0, foam_level);

        float foam_noise_val = fbm_voronoi(foam_uv) * effective_emergence;

        // Muestra desplazada para crear borde oscuro que simula grosor
        vec2 foam_uv_shadow = (world_pos.xz + foam_edge_offset) * foam_noise_scale + warp;
        float foam_noise_shadow_val = fbm_voronoi(foam_uv_shadow) * effective_emergence;

        float combined_noise  = foam_noise_val + foam_level;
        float combined_shadow = foam_noise_shadow_val + foam_level;

        foam_mask_primary = smoothstep(foam_cutoff + 0.5, foam_cutoff + 0.6, combined_noise);
        float shadow_shape = smoothstep(foam_cutoff + 0.5, foam_cutoff + 0.6, combined_shadow);
        foam_mask_shadow = clamp(shadow_shape - foam_mask_primary, 0.0, 1.0);
    }

    // Burbujas internas: textura Voronoi adicional dentro de la espuma
    float voronoi_val = 1.0 - sqrt(voronoi_noise(world_pos.xz * voronoi_scale + warp));
    voronoi_val = smoothstep(0.2, 0.8, voronoi_val);
    float bubble_alpha = 1.0 - clamp((1.0 - voronoi_val) * voronoi_strength, 0.0, 1.0);

    // En z_dif ≈ 0 (contacto exacto con el terreno): difuminado blanco suave.
    // Se atenúa el Voronoi para que no quede un borde duro, y se superpone un glow.
    float shore_contact = smoothstep(shore_soft_width, 0.0, max(z_dif, 0.0)) * depth_foam_factor;
    float foam_soften   = 1.0 - shore_contact * 0.85;

    final_albedo = mix(final_albedo, foam_edge_color, foam_mask_shadow * foam_soften);
    final_albedo = mix(final_albedo, foam_color, foam_mask_primary * bubble_alpha * foam_soften);
    final_albedo = mix(final_albedo, foam_color, shore_contact);
    // Screen blend: añade luz sin quemar los colores existentes (A + B - A*B)
    final_albedo = final_albedo + caustics_contrib - final_albedo * caustics_contrib;

    ALBEDO = clamp(final_albedo, vec3(0.0), vec3(1.0));

    // Alpha: se desvanece suavemente en la línea de contacto con el terreno
    float shore_alpha_fade = smoothstep(0.0, shore_soft_width, max(z_dif, 0.0));
    float base_alpha = mix(surface_alpha, deep_alpha, opacity_factor);
    float refraction_alpha = refraction_alpha_floor * (1.0 - opacity_factor);
    float foam_opacity = max(max(foam_mask_primary * bubble_alpha, foam_mask_shadow) * foam_soften, shore_contact);
    float final_alpha = max(max(base_alpha, refraction_alpha), foam_opacity);
    final_alpha *= shore_alpha_fade;
    final_alpha = mix(final_alpha, 1.0, edge_disable);
    ALPHA = clamp(final_alpha, 0.0, deep_alpha);

    ROUGHNESS = mix(roughness, 0.8, (foam_mask_primary * bubble_alpha) + foam_mask_shadow);
    SPECULAR = 0.5;
    METALLIC = metallic;
	
}
