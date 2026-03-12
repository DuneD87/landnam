shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// ============================================================
// ATMOSPHERIC SCATTERING SHADER - Spherical Planet (Godot 4)
// ============================================================

// --- Configuración general ---
group_uniforms atmosphere;
uniform vec3 atmosphere_color : source_color = vec3(0.25, 0.52, 1.0);
uniform vec3 sunset_color : source_color = vec3(1.0, 0.35, 0.05);
uniform float atmosphere_intensity : hint_range(0.0, 5.0) = 1.5;
uniform float atmosphere_density : hint_range(0.5, 10.0) = 3.0;
uniform float atmosphere_falloff : hint_range(0.5, 10.0) = 4.0;

// --- Sol y scattering ---
group_uniforms sun;
uniform vec3 sun_direction = vec3(0.577, 0.577, 0.577);
uniform float sun_disk_size : hint_range(0.0, 0.2) = 0.02;
uniform float sun_disk_intensity : hint_range(0.0, 10.0) = 3.0;
uniform float mie_strength : hint_range(0.0, 2.0) = 0.5;
uniform float mie_directionality : hint_range(0.0, 0.999) = 0.76;

// --- Sunset / sunrise ---
group_uniforms sunset;
uniform float sunset_sharpness : hint_range(0.5, 10.0) = 3.0;
uniform float sunset_spread : hint_range(0.0, 1.0) = 0.4;
uniform vec3 night_sky_color : source_color = vec3(0.01, 0.01, 0.03);

// --- Depth fade ---
group_uniforms depth_fade;
uniform float depth_fade_distance : hint_range(0.0, 500.0) = 150.0;
uniform bool use_depth_fade = true;

uniform sampler2D DEPTH_TEX : hint_depth_texture, filter_linear;

// ============================================================
// Funciones auxiliares
// ============================================================

float henyey_greenstein(float cos_theta, float g) {
    float g2 = g * g;
    float denom = 1.0 + g2 - 2.0 * g * cos_theta;
    return (1.0 - g2) / (4.0 * PI * pow(denom, 1.5));
}

float rayleigh_phase(float cos_theta) {
    return 0.75 * (1.0 + cos_theta * cos_theta);
}

// ============================================================
// Fragment
// ============================================================

void fragment() {
    // Con cull_disabled, asegurar normal hacia la cámara
    vec3 normal_out = FRONT_FACING ? NORMAL : -NORMAL;
    vec3 view_dir = normalize(VIEW);

    // --- Fresnel atmosférico ---
    float ndotv = clamp(dot(normal_out, view_dir), 0.0, 1.0);
    float fresnel = pow(1.0 - ndotv, atmosphere_falloff);
    float atmo_density = fresnel * atmosphere_density;

    // --- Sun en view space ---
    vec3 sun_dir_view = normalize((VIEW_MATRIX * vec4(normalize(sun_direction), 0.0)).xyz);
    float cos_theta = dot(view_dir, sun_dir_view);

    // --- Scattering ---
    float rayleigh = rayleigh_phase(cos_theta);
    float mie = henyey_greenstein(cos_theta, mie_directionality) * mie_strength;

    // --- Día / noche ---
    float sun_dot_normal = dot(normal_out, sun_dir_view);
    float day_factor = clamp(sun_dot_normal * 2.0 + 0.5, 0.0, 1.0);

    // --- Color ---
    float horizon_factor = 1.0 - abs(sun_dot_normal);
    float sunset_mask = pow(horizon_factor, sunset_sharpness);
    float sun_horizon = clamp(dot(normal_out, sun_dir_view) * 0.5 + 0.5, 0.0, 1.0);
    sunset_mask *= smoothstep(0.0, sunset_spread, sun_horizon);

    vec3 sky_color = mix(atmosphere_color, sunset_color, sunset_mask);
    sky_color += sunset_color * mie * 0.5;
    sky_color *= rayleigh * 0.3 + 0.7;
    sky_color = mix(night_sky_color, sky_color, day_factor);

    // --- Disco solar ---
    float sun_disk = smoothstep(1.0 - sun_disk_size, 1.0, cos_theta);
    sky_color += vec3(1.0, 0.95, 0.8) * sun_disk * sun_disk_intensity * day_factor;

    // --- Depth fade ---
    float alpha = clamp(atmo_density * atmosphere_intensity, 0.0, 1.0);

    if (use_depth_fade) {
        float raw_depth = texture(DEPTH_TEX, SCREEN_UV).r;
        if (raw_depth < 1.0) {
            vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
            vec4 view_pos = INV_PROJECTION_MATRIX * ndc;
            float scene_depth = -view_pos.z / view_pos.w;
            float frag_depth = -VERTEX.z;
            float depth_diff = scene_depth - frag_depth;
            alpha *= smoothstep(0.0, depth_fade_distance, depth_diff);
        }
    }

    ALBEDO = sky_color;
    ALPHA = alpha;
}
