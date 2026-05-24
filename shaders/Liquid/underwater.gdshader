shader_type spatial;
render_mode unshaded, depth_draw_always;
uniform float u_sphere_radius = 5.0;
uniform vec3 sun_direction = vec3(1.0, 0.0, 0.0);
uniform vec4 fog_color : source_color = vec4(0.7, 0.8, 0.9, 1.0);
uniform vec4 deep_fog_color : source_color = vec4(0.1, 0.2, 0.3, 1.0);
uniform vec4 abyss_fog_color : source_color = vec4(0.1, 0.1, 0.15, 1.0);
uniform float fog_density : hint_range(0.0, 1.0) = 0.5;
uniform float camera_depth_attenuation : hint_range(0.0, 2.0) = 0.5;
uniform float max_useful_depth = 250.0;
uniform float deep_transition_depth = 100.0;
uniform float abyss_transition_depth = 250.0;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

uniform float caustic_intensity : hint_range(0.0, 5.0) = 0.5;
uniform float caustic_scale : hint_range(0.1, 10.0) = 0.2;
uniform float caustic_speed : hint_range(0.0, 2.0) = 0.1;
uniform float caustic_contrast : hint_range(0.1, 5.0) = 1.5;
uniform float caustics_depth_factor : hint_range(0.1, 1.0) = 0.06;
uniform int caustic_iterations : hint_range(3, 8) = 5;
uniform float caustic_inten_factor : hint_range(0.001, 0.02) = 0.001;
uniform float caustic_max_view_distance = 25.0;

uniform float godray_intensity : hint_range(0.0, 5.0) = 1.9;
uniform float godray_decay : hint_range(0.5, 1.0) = 0.88;
uniform float godray_exposure : hint_range(0.0, 2.0) = 0.4;
uniform int godray_samples : hint_range(10, 50) = 10;
// Nuevos uniforms para controlar la atenuación de god rays
uniform float godray_max_depth : hint_range(10.0, 100.0) = 35.0; // Profundidad máxima donde los god rays son visibles
uniform float godray_fade_start : hint_range(5.0, 50.0) = 10.0; // Profundidad donde empiezan a desvanecerse
uniform float godray_density : hint_range(0.0, 2.0) = 0.12;
uniform float godray_surface_scale : hint_range(0.001, 1.0) = 0.1;
uniform float godray_surface_speed : hint_range(0.0, 2.0) = 0.12;
uniform float godray_surface_contrast : hint_range(0.5, 8.0) = 3.0;
uniform float godray_light_absorption : hint_range(0.0, 1.0) = 0.08;
uniform float godray_view_absorption : hint_range(0.0, 1.0) = 0.025;
uniform float godray_forward_scatter_power : hint_range(0.5, 12.0) = 3.0;
uniform float godray_min_phase : hint_range(0.0, 1.0) = 0.15;

varying vec3 v_volume_center_viewspace;
varying vec3 v_ray_origin;
varying vec3 v_ray_dir;
varying vec3 v_camera_world_pos;
varying vec3 v_sphere_center_world;
varying float v_camera_depth_actual;
varying float v_camera_depth_factor;

vec3 calculate_depth_fog_color(float depth_meters) {
    if (depth_meters <= deep_transition_depth) {
        float t = clamp(depth_meters / deep_transition_depth, 0.0, 1.0);
        return mix(fog_color.rgb, deep_fog_color.rgb, t);
    } else if (depth_meters <= abyss_transition_depth) {
        float t = clamp((depth_meters - deep_transition_depth) / (abyss_transition_depth - deep_transition_depth), 0.0, 1.0);
        return mix(deep_fog_color.rgb, abyss_fog_color.rgb, t);
    } else {
        return abyss_fog_color.rgb;
    }
}

vec3 hash3(vec3 p) {
    p = vec3(dot(p, vec3(127.1, 311.7, 74.7)),
             dot(p, vec3(269.5, 183.3, 246.1)),
             dot(p, vec3(113.5, 271.9, 124.6)));
    return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float worley3d_static(vec3 p, float scale) {
    p *= scale;

    vec3 ip = floor(p);
    vec3 fp = fract(p);

    float min_dist = 1.0;

    for (int z = -1; z <= 1; z++) {
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                vec3 neighbor = vec3(float(x), float(y), float(z));

                vec3 point = hash3(ip + neighbor);
                point = 0.5 + 0.5 * point;

                vec3 diff = neighbor + point - fp;
                float dist = length(diff);

                min_dist = min(min_dist, dist);
            }
        }
    }

    return min_dist;
}

float worley3d(vec3 p, float scale) {
    p *= scale;
    vec3 ip = floor(p);
    vec3 fp = fract(p);

    float min_dist = 1.0;

    for (int z = -1; z <= 1; z++) {
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                vec3 neighbor = vec3(float(x), float(y), float(z));
                vec3 point = hash3(ip + neighbor);
                point = 0.5 + 0.5 * sin(TIME * 0.5 + 6.2831 * point);
                vec3 diff = neighbor + point - fp;
                float dist = length(diff);
                min_dist = min(min_dist, dist);
            }
        }
    }

    return min_dist;
}

float generate_caustics(vec3 world_pos) {
    vec3 sample_pos = world_pos * caustic_scale;
    sample_pos.xz += TIME * caustic_speed * sun_direction.xy;
    sample_pos += (v_camera_world_pos * 0.001);

    float caustic = 0.0;
    float amplitude = 1.0;
    float total_amplitude = 0.0;
    float frequency = 1.0;

    for (int i = 0; i < 4; i++) {
        caustic += amplitude * (1.0 - worley3d(sample_pos * frequency, 1.0));
        total_amplitude += amplitude;
        amplitude *= 0.5;
        frequency *= 1.8;
    }

    caustic /= total_amplitude;
    caustic = pow(caustic, caustic_contrast);

    // Reset for previous sample
    float caustic_prev = 0.0;
    amplitude = 1.0;  // Reset
    total_amplitude = 0.0;  // Reset
    frequency = 1.0;  // Reset

    vec3 sample_pos_prev = sample_pos;
    sample_pos_prev.xz -= caustic_speed * sun_direction.xy * 0.1;

    for (int i = 0; i < 4; i++) {
        caustic_prev += amplitude * (1.0 - worley3d(sample_pos_prev * frequency, 1.0));
        total_amplitude += amplitude;
        amplitude *= 0.5;
        frequency *= 1.8;
    }

    caustic_prev /= total_amplitude;
    caustic_prev = pow(caustic_prev, caustic_contrast);
    caustic = mix(caustic, caustic_prev, 0.3);

    return caustic;
}

vec2 ray_sphere(vec3 center, float radius, vec3 ro, vec3 rd) {
    vec3 oc = ro - center;
    float b = dot(oc, rd);
    float c = dot(oc, oc) - radius * radius;
    float discriminant = b * b - c;

    if (discriminant < 0.0) {
        return vec2(-1.0, -1.0);
    }

    float sqrt_disc = sqrt(discriminant);
    return vec2(-b - sqrt_disc, -b + sqrt_disc);
}

float caustic_x(float x, float power, float gtime) {
    float p = mod(x * TAU, TAU) - 250.0;
    float time = gtime * 0.5 + 23.0;

    float i = p;
    float c = 1.0;
    float inten = 0.005;

    for (int n = 0; n < 3; n++) {
        float t = time * (1.0 - (3.5 / float(n + 1)));
        i = p + cos(t - i) + sin(t + i);
        c += 1.0 / length(p / (sin(i + t) / inten));
    }

    c /= float(caustic_iterations);
    c = 1.17 - pow(c, power);

    return c;
}

float god_rays(vec2 uv, float time) {
    float light = 0.0;
    light += pow(caustic_x((uv.x + 0.08 * uv.y) / 1.7 + 0.5, 1.8, time * 0.65), 10.0) * 0.05;
    light -= pow((1.0 - uv.y) * 0.3, 2.0) * 0.2;
    light += pow(caustic_x(sin(uv.x), 0.3, time * 0.7), 9.0) * 0.4;
    light += pow(caustic_x(cos(uv.x * 2.3), 0.3, time * 1.3), 4.0) * 0.1;
    light -= pow((1.0 - uv.y) * 0.3, 3.0);
    light = clamp(light, 0.0, 100.0);

    return light;
}

vec3 safe_perpendicular(vec3 n) {
    vec3 a = abs(n.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    return normalize(cross(a, n));
}

float godray_surface_mask(vec3 surface_world_pos, vec3 light_dir_to_sun, float sun_facing) {
    vec3 tangent = safe_perpendicular(light_dir_to_sun);
    vec3 bitangent = normalize(cross(light_dir_to_sun, tangent));

    vec3 rel = surface_world_pos - v_sphere_center_world;

    vec2 suv = vec2(
        dot(rel, tangent),
        dot(rel, bitangent)
    ) * godray_surface_scale;

    // Patrón espacial estático.
    vec3 p1 = vec3(suv, 0.0);
    vec3 p2 = vec3(suv * 2.15 + vec2(13.7, 8.4), 4.2);

    float n1 = 1.0 - worley3d_static(p1, 1.0);
    float n2 = 1.0 - worley3d_static(p2, 1.0);

    float mask = n1 * 0.75 + n2 * 0.25;

    // Convertimos el ruido en manchas/ventanas de entrada de luz.
    float focus = smoothstep(0.35, 0.98, sun_facing);
    float window_threshold = mix(0.74, 0.46, focus);

    mask = smoothstep(window_threshold, 0.95, mask);
    mask = pow(mask, godray_surface_contrast);

    // Flicker temporal: cambia la intensidad, no la posición.
    float phase_seed = dot(rel, vec3(0.017, 0.031, 0.023));
    float shimmer_time = TIME * godray_surface_speed;

    float flicker_a = sin(shimmer_time * 0.45 + phase_seed * 3.1);
    float flicker_b = sin(shimmer_time * 0.83 + phase_seed * 1.4);
    float flicker_c = sin(shimmer_time * 1.21 + phase_seed * 0.7);

    float flicker = flicker_a * 0.5 + flicker_b * 0.3 + flicker_c * 0.2;
    flicker = 0.65 + 0.35 * flicker;

    // Evita apagados demasiado bruscos.
    flicker = clamp(flicker, 0.25, 1.0);

    return mask * flicker * focus;
}

vec3 volumetric_water_god_rays(float t_start, float t_end, vec3 ray_dir_view, mat4 inv_view_matrix, vec2 screen_uv) {
    vec3 light_dir_to_sun = normalize(sun_direction);

    vec3 ray_dir_world = normalize(
        (inv_view_matrix * vec4(ray_dir_view, 0.0)).xyz
    );

    float ray_length = t_end - t_start;

    if (ray_length <= 0.0) {
        return vec3(0.0);
    }

    float step_len = ray_length / float(godray_samples);

    float jitter = fract(
        sin(dot(screen_uv, vec2(12.9898, 78.233))) * 43758.5453
    );

    float forward_phase = pow(
        max(dot(ray_dir_world, light_dir_to_sun), 0.0),
        godray_forward_scatter_power
    );

    float phase = mix(godray_min_phase, 1.0, forward_phase);

    vec3 accumulated = vec3(0.0);

    for (int i = 0; i < 50; i++) {
        if (i >= godray_samples) {
            break;
        }

        float t = t_start + (float(i) + jitter) * step_len;

        vec3 sample_view = ray_dir_view * t;
        vec4 sample_world_4 = inv_view_matrix * vec4(sample_view, 1.0);
        vec3 sample_world = sample_world_4.xyz / sample_world_4.w;

        vec3 center_to_sample = sample_world - v_sphere_center_world;
        float radial_dist = length(center_to_sample);
        float radial_depth = u_sphere_radius - radial_dist;

        if (radial_depth > 0.0) {
            vec2 sun_exit = ray_sphere(
                v_sphere_center_world,
                u_sphere_radius,
                sample_world,
                light_dir_to_sun
            );

            float light_path = max(sun_exit.y, 0.0);

            vec3 entry_world = sample_world + light_dir_to_sun * light_path;
            vec3 entry_normal = normalize(entry_world - v_sphere_center_world);

            float sun_facing_raw = max(dot(entry_normal, light_dir_to_sun), 0.0);
            float sun_facing = smoothstep(0.35, 0.95, sun_facing_raw);
			sun_facing = pow(sun_facing, 4.0);

            float surface_depth_fade =
                1.0 - smoothstep(godray_fade_start, godray_max_depth, radial_depth);

            float light_path_fade = exp(-light_path * godray_light_absorption);
            float view_fade = exp(-(t - t_start) * godray_view_absorption);
            float sample_progress = float(i) / max(float(godray_samples - 1), 1.0);
            float sample_decay = pow(godray_decay, sample_progress * 12.0);

            float mask = godray_surface_mask(entry_world, light_dir_to_sun, sun_facing_raw);

            float density =
                mask *
                sun_facing *
                surface_depth_fade *
                light_path_fade *
                view_fade *
                sample_decay;

            accumulated += vec3(density) * step_len * godray_density;
        }
    }

    return accumulated * godray_intensity * godray_exposure * phase;
}

// Nueva función para calcular la atenuación de god rays basada en profundidad
float calculate_godray_depth_attenuation(float depth_meters) {
    if (depth_meters <= godray_fade_start) {
        // Totalmente visible hasta godray_fade_start metros
        return 1.0;
    } else if (depth_meters >= godray_max_depth) {
        // Totalmente invisible después de godray_max_depth metros
        return 0.0;
    } else {
        // Atenuación gradual entre godray_fade_start y godray_max_depth
        float fade_range = godray_max_depth - godray_fade_start;
        float fade_progress = (depth_meters - godray_fade_start) / fade_range;
        // Usar smoothstep para una transición más suave
        return 1.0 - smoothstep(0.0, 1.0, fade_progress);
    }
}

void vertex() {
    POSITION = vec4(VERTEX.xy, 1.0, 1.0);

    vec4 world_center = MODEL_MATRIX * vec4(0, 0, 0, 1);
    v_volume_center_viewspace = (VIEW_MATRIX * world_center).xyz;
    v_sphere_center_world = world_center.xyz / world_center.w;

    v_ray_origin = vec3(0.0, 0.0, 0.0);

    vec4 vertex_viewspace = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
    v_ray_dir = normalize(vertex_viewspace.xyz);

    vec4 camera_world = INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
    v_camera_world_pos = camera_world.xyz / camera_world.w;

    float camera_dist_to_center = length(v_camera_world_pos - v_sphere_center_world);
    float camera_depth_in_sphere = max(0.0, u_sphere_radius - camera_dist_to_center);

    v_camera_depth_actual = camera_depth_in_sphere;
    v_camera_depth_factor = clamp(camera_depth_in_sphere / max_useful_depth, 0.0, 1.0);
}

void fragment() {
	if (length(CAMERA_POSITION_WORLD - v_sphere_center_world) > u_sphere_radius)
	{
		discard;
	}
    float nonlinear_depth = texture(depth_texture, SCREEN_UV).x;

    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, nonlinear_depth);
    vec4 view_coords = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    view_coords.xyz /= view_coords.w;
    float scene_distance = length(view_coords.xyz);

    vec3 ray_dir = normalize(view_coords.xyz);

    vec2 t_range = ray_sphere(v_volume_center_viewspace, u_sphere_radius, v_ray_origin, ray_dir);

    float t_start = max(t_range.x, 0.0);
    float hit_distance = min(t_range.y, scene_distance);
    float t_end = hit_distance;

    if (t_end <= t_start) {
        discard;
    }

    float distance_in_fog = t_end - t_start;
    float fog_amount = 1.0 - exp(-fog_density * distance_in_fog);

    // Reconstruct view-space pos at hit_distance, then to world
    vec3 hit_view_pos = ray_dir * mix(t_start, t_end, 0.9);
    vec3 hit_view_pos_real = ray_dir * hit_distance;
    vec4 world_pos_from_view = INV_VIEW_MATRIX * vec4(hit_view_pos, 1.0);
    vec3 world_pos = world_pos_from_view.xyz / world_pos_from_view.w;
	vec3 direction_to_center = world_pos - v_sphere_center_world;
	float distance_to_pos = length(world_pos - CAMERA_POSITION_WORLD);
	float caustic_fade_distance = smoothstep(0.0, 1.0, caustic_max_view_distance / distance_to_pos);
    vec3 camera_adjusted_fog = calculate_depth_fog_color(v_camera_depth_actual);
    float camera_attenuation = exp(-v_camera_depth_factor * camera_depth_attenuation);

    float caustic_effect = 0.0;
    float dist_to_center = length(direction_to_center);
    float depth_in_sphere = u_sphere_radius - dist_to_center;
    vec3 normal = normalize(direction_to_center);
    float light_influence = max(0.0, dot(normal, normalize(sun_direction)));
    light_influence = pow(light_influence, 2.0);
    float caustic_attenuation = exp(-depth_in_sphere * caustics_depth_factor);

    if (dist_to_center <= u_sphere_radius) {
        caustic_effect = generate_caustics(world_pos) * caustic_intensity * light_influence * caustic_fade_distance;
        caustic_effect *= caustic_attenuation;
    }

    vec3 final_color = camera_adjusted_fog;
    if (caustic_effect > 0.0) {
        vec3 caustic_color = mix(vec3(1.0), camera_adjusted_fog, 0.3);
        final_color += caustic_color * caustic_effect * 0.8 * camera_attenuation;
    }

    vec3 godrays = volumetric_water_god_rays(t_start, t_end, ray_dir, INV_VIEW_MATRIX, SCREEN_UV);

	vec3 godray_color = mix(vec3(1.0), fog_color.rgb, 0.35);

	final_color += godrays * godray_color * camera_attenuation;

    ALBEDO = final_color;
    ALPHA = fog_amount * fog_color.a;

    EMISSION = final_color * fog_amount * 0.3 +
               vec3(caustic_effect * 0.4 * camera_attenuation);
}
