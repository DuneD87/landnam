shader_type spatial;
render_mode unshaded;
// Core uniforms (set by script)
uniform float u_sphere_radius = 5.0;
uniform float u_volume_height = 10.0;
uniform float u_clip_mode = 0.0;
uniform mat4 u_world_to_model_matrix;

// Fog parameters
uniform float fog_density : hint_range(0.0, 2.0) = 0.8;
uniform vec4 fog_color : source_color = vec4(0.7, 0.8, 0.9, 1.0);
uniform float absorption : hint_range(0.0, 1.0) = 0.2;
uniform float scattering : hint_range(0.0, 1.0) = 0.4;
uniform float noise_scale : hint_range(0.1, 10.0) = 2.0;
uniform float noise_speed : hint_range(0.0, 1.0) = 0.1;
uniform float edge_softness : hint_range(0.0, 1.0) = 0.3;
uniform float emission_strength : hint_range(0.5, 5.0) = 2.0;

// Raymarch parameters
uniform int max_steps = 64;
uniform float step_size : hint_range(0.01, 0.5) = 0.1;

// Depth texture for proper integration
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

// Varyings for view space calculations
varying vec3 v_volume_center_viewspace;
varying vec3 v_ray_origin;
varying vec3 v_ray_dir;

// Simple noise function
float hash(vec3 p) {
    p = fract(p * 0.3183099 + 0.1);
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3D(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    return mix(mix(mix(hash(i + vec3(0, 0, 0)), 
                       hash(i + vec3(1, 0, 0)), f.x),
                   mix(hash(i + vec3(0, 1, 0)), 
                       hash(i + vec3(1, 1, 0)), f.x), f.y),
               mix(mix(hash(i + vec3(0, 0, 1)), 
                       hash(i + vec3(1, 0, 1)), f.x),
                   mix(hash(i + vec3(0, 1, 1)), 
                       hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p, float time) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    
    for (int i = 0; i < 3; i++) {
        value += amplitude * noise3D(p * frequency + vec3(time * noise_speed));
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    
    return value;
}

// Ray-sphere intersection
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

// Get density at position
float get_density(vec3 pos, vec3 center, float time) {
    float dist_to_center = length(pos - center);
    
    if (dist_to_center > u_sphere_radius) {
        return 0.0;
    }
    
    float density = fog_density;
    
    // Temporarily disable for uniform underwater (re-enable for cloud variation)
    // vec3 noise_pos = (pos - center) * noise_scale;
    // float noise = fbm(noise_pos, time);
    // density *= (0.7 + 0.3 * noise);
    
    // if (edge_softness > 0.01) {
    //     float edge_fade = 1.0 - smoothstep(u_sphere_radius * (1.0 - edge_softness), u_sphere_radius, dist_to_center);
    //     density *= edge_fade;
    // }
    
    return density;
}

void vertex() {
    // Handle clip modes similar to atmosphere shader
    if (u_clip_mode > 0.5) {
        // Near mode: fullscreen quad
        POSITION = vec4(VERTEX.xy, 1.0, 1.0);
    }
    
    // Calculate volume center in view space
    vec4 world_center = MODEL_MATRIX * vec4(0, 0, 0, 1);
    v_volume_center_viewspace = (VIEW_MATRIX * world_center).xyz;
    
    // Setup ray in view space
    v_ray_origin = vec3(0.0, 0.0, 0.0); // Camera position in view space
    vec4 vertex_viewspace = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
    v_ray_dir = normalize(vertex_viewspace.xyz);
}

void fragment() {
   	float nonlinear_depth = texture(depth_texture, SCREEN_UV).x;
    
    // Convert to view space depth
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, nonlinear_depth);
    vec4 view_coords = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    view_coords.xyz /= view_coords.w;
    float linear_depth = -view_coords.z;
    
    // In clip mode, recalculate ray direction from screen position
    vec3 ray_dir = v_ray_dir;
    if (u_clip_mode > 0.5) {
        ray_dir = normalize(view_coords.xyz);
    }
    
    vec2 t_range = ray_sphere(v_volume_center_viewspace, u_sphere_radius, v_ray_origin, ray_dir);
    
    // Initialize with transparent
    ALBEDO = vec3(0.0);
    EMISSION = vec3(0.0);
    ALPHA = 0.0;
    
    // Handle no intersection
    if (t_range.x > t_range.y || t_range.y < 0.0) {
        discard;  // No wireframe needed; use for debug only if desired
    }
    
    // Determine raymarch range
    float t_start = max(t_range.x, 0.0);
    float t_end = min(t_range.y, linear_depth);
    
    // Check if camera is inside volume
    bool is_inside = length(v_volume_center_viewspace) < u_sphere_radius;
    if (is_inside) {
        t_start = 0.0;
        t_end = min(t_range.y, linear_depth);
        // Optional: For "infinite" underwater fog when inside, uncomment to ignore exit and apply to full scene depth
        // t_end = linear_depth;
    }
    
    if (t_end <= t_start) {
        discard;
    }
    
    // For underwater uniformity: Assume homogeneous density (disable noise for now)
    // Comment out noise in get_density or set variation to 0 here
    float distance = t_end - t_start;
    float density = fog_density;  // Base density, no noise for smooth effect
    
    // Analytical solution for homogeneous fog (smooth, no steps/artifacts)
    float extinction_coeff = density * (absorption + scattering);
    float optical_depth = extinction_coeff * distance;
    float transmittance = exp(-optical_depth);
    
    vec3 accumulated_color = vec3(0.0);
    if (extinction_coeff > 0.001) {
        // Approximate in-scattered light (single scattering assumption)
        accumulated_color = fog_color.rgb * (scattering / (absorption + scattering)) * (1.0 - transmittance);
    }
    
    float accumulated_alpha = 1.0 - transmittance;
    
    // Optional: Incorporate volume_height as a vertical clamp (e.g., for ocean layer)
    // Adjust density based on ray height traversal (simple approximation)
    // vec3 start_pos = v_ray_origin + ray_dir * t_start;
    // vec3 end_pos = v_ray_origin + ray_dir * t_end;
    // float avg_height = (start_pos.y + end_pos.y) * 0.5 - v_volume_center_viewspace.y;
    // if (abs(avg_height) > u_volume_height * 0.5) {
    //     density *= smoothstep(u_volume_height * 0.5, u_volume_height * 0.4, abs(avg_height));  // Fade out beyond height
    //     // Recompute optical_depth, transmittance, etc., with adjusted density
    // }
    
    // Fallback to raymarch loop if noise/edge_softness needed (for debug or variation)
    // Uncomment if you re-enable noise; otherwise, keep analytical for smoothness
    /*
    float transmittance = 1.0;
    vec3 accumulated_color = vec3(0.0);
    float accumulated_alpha = 0.0;
    float actual_step = (t_end - t_start) / float(max_steps);
    float t = t_start;
    for (int i = 0; i < max_steps && t < t_end; i++) {
        vec3 pos = v_ray_origin + ray_dir * t;
        float density = get_density(pos, v_volume_center_viewspace, TIME);
        if (density > 0.001) {
            float extinction = density * (absorption + scattering) * actual_step;
            float step_transmittance = exp(-extinction);
            vec3 step_color = fog_color.rgb * density * scattering;
            accumulated_color += step_color * transmittance * actual_step;
            transmittance *= step_transmittance;
            accumulated_alpha += (1.0 - step_transmittance) * (1.0 - accumulated_alpha);
        }
        t += actual_step;
        if (transmittance < 0.01) break;
    }*/
   
    
    // Output
    ALBEDO = accumulated_color;
    ALPHA = clamp(accumulated_alpha, 0.0, 0.95);
    EMISSION = accumulated_color * emission_strength;
}