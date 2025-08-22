shader_type spatial;
render_mode unshaded;
uniform float u_sphere_radius = 5.0;
uniform vec3 sun_direction = vec3(1.0, 0.0, 0.0);
uniform vec4 fog_color : source_color = vec4(0.7, 0.8, 0.9, 1.0);
uniform vec4 deep_fog_color : source_color = vec4(0.1, 0.2, 0.3, 1.0);
uniform vec4 abyss_fog_color : source_color = vec4(0.1, 0.1, 0.15, 1.0);
uniform float fog_density : hint_range(0.0, 1.0) = 0.5;
uniform float camera_depth_attenuation : hint_range(0.0, 2.0) = 0.5;
uniform float max_useful_depth = 500.0;
uniform float deep_transition_depth = 100.0;
uniform float abyss_transition_depth = 250.0;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

uniform float caustic_intensity : hint_range(0.0, 5.0) = 0.2;
uniform float caustic_scale : hint_range(0.1, 10.0) = 0.2;
uniform float caustic_speed : hint_range(0.0, 2.0) = 0.1;
uniform float caustic_contrast : hint_range(0.1, 5.0) = 1.5;
uniform float caustics_depth_factor : hint_range(0.1, 1.0) = 0.2;

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
    sample_pos.xz += TIME * caustic_speed * normalize(sun_direction.xz);
    
    float caustic = 0.0;
    caustic += 1.0 - worley3d(sample_pos, 1.0);
    caustic += 0.5 * (1.0 - worley3d(sample_pos * 1.5, 1.0));
    caustic += 0.25 * (1.0 - worley3d(sample_pos * 2.0, 1.0));
    
    caustic /= 1.75;
    caustic = pow(caustic, caustic_contrast);
    
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
    float nonlinear_depth = texture(depth_texture, SCREEN_UV).x;

    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, nonlinear_depth);
    vec4 view_coords = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    view_coords.xyz /= view_coords.w;
    float scene_depth = -view_coords.z;

    vec3 ray_dir = normalize(view_coords.xyz);

    vec2 t_range = ray_sphere(v_volume_center_viewspace, u_sphere_radius, v_ray_origin, ray_dir);

    float t_start = max(t_range.x, 0.0);
    float t_end = min(t_range.y, scene_depth);

    if (t_end <= t_start) {
        discard;
    }

    float distance_in_fog = t_end - t_start;
    float fog_amount = 1.0 - exp(-fog_density * distance_in_fog);

    vec4 world_pos_from_view = INV_VIEW_MATRIX * vec4(view_coords.xyz, 1.0);
    vec3 world_pos = world_pos_from_view.xyz / world_pos_from_view.w;
    
    vec3 camera_adjusted_fog = calculate_depth_fog_color(v_camera_depth_actual);
    float camera_attenuation = exp(-v_camera_depth_factor * camera_depth_attenuation);
    
    float caustic_effect = 0.0;
    float dist_to_center = length(world_pos - v_sphere_center_world);
    float depth_in_sphere = u_sphere_radius - dist_to_center;
    
    if (dist_to_center < u_sphere_radius) {
        caustic_effect = generate_caustics(world_pos) * caustic_intensity;
        float caustic_attenuation = exp(-depth_in_sphere * caustics_depth_factor);
        caustic_effect *= caustic_attenuation;
    }
    
    vec3 final_color = camera_adjusted_fog;
    
    if (caustic_effect > 0.0) {
        vec3 caustic_color = mix(vec3(1.0), camera_adjusted_fog, 0.3);
        final_color += caustic_color * caustic_effect * 0.8 * camera_attenuation;
    }

    ALBEDO = final_color;
    ALPHA = fog_amount * fog_color.a;

    EMISSION = final_color * fog_amount * 0.3 + vec3(caustic_effect * 0.4 * camera_attenuation);
}
