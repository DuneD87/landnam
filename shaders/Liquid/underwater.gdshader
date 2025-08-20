shader_type spatial;
render_mode unshaded;

// Core uniforms (set by script)
uniform float u_sphere_radius = 500000.0;
uniform float u_volume_height = 10.0;
uniform mat4 u_world_to_model_matrix;

// Basic fog parameters
uniform float fog_density : hint_range(0.0, 2.0) = 0.8;
uniform vec4 fog_color : source_color = vec4(0.4, 0.7, 0.9, 1.0);
uniform float absorption : hint_range(0.0, 1.0) = 0.2;
uniform float scattering : hint_range(0.0, 1.0) = 0.4;
uniform float emission_strength : hint_range(0.5, 5.0) = 2.0;

// Enhanced underwater parameters
uniform float water_clarity : hint_range(0.1, 10.0) = 0.1;
uniform float depth_color_shift : hint_range(0.0, 2.0) = 2.0;
uniform vec3 water_tint : source_color = vec3(0.1, 0.1, 0.9);
uniform float caustics_strength : hint_range(0.0, 3.0) = 3.0;
uniform float particle_density : hint_range(0.0, 2.0) = 1.5;
uniform float current_speed : hint_range(0.0, 1.0) = 0.02;
uniform float turbulence_strength : hint_range(0.0, 1.0) = 0.3;
uniform float god_rays_intensity : hint_range(0.0, 3.0) = 1.5;
uniform vec3 sun_direction = vec3(0.3, 1.0, 0.2);

// Noise parameters
uniform float noise_scale : hint_range(0.1, 10.0) = 2.0;
uniform float noise_speed : hint_range(0.0, 1.0) = 0.1;
uniform float edge_softness : hint_range(0.0, 1.0) = 0.3;

// Raymarch parameters
uniform int max_steps = 32;
uniform float step_size : hint_range(0.01, 0.5) = 0.1;

// Depth texture
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

// Varyings
varying vec3 v_volume_center_viewspace;
varying vec3 v_ray_origin;
varying vec3 v_ray_dir;
varying mat4 v_inv_view_matrix;  // Nueva variable para transformar de vista a mundo

// Enhanced noise functions
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

float fbm(vec3 p, float time, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    
    for (int i = 0; i < octaves; i++) {
        value += amplitude * noise3D(p * frequency + vec3(time * noise_speed));
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    
    return value;
}

// Spectral absorption for realistic underwater color
vec3 spectral_absorption(float distance) {
    // Real water absorption coefficients (scaled for visibility)
    vec3 absorption_coeffs = vec3(0.45, 0.1, 0.01) * (1.0 / water_clarity);
    return exp(-absorption_coeffs * distance * 0.01);
}

// Caustics pattern for light refraction effects
float caustics_pattern(vec3 pos, float time) {
    vec3 p = pos * 0.8;
    
    // Multiple wave layers for realistic caustics
    float wave1 = sin(p.x * 4.0 + time * 2.0) * sin(p.z * 3.0 + time * 1.5);
    float wave2 = sin(p.x * 2.5 - time * 1.8) * sin(p.z * 4.5 - time * 2.2);
    float wave3 = sin(p.x * 6.0 + time * 1.2) * sin(p.z * 2.0 - time * 1.9);
    
    float combined = (wave1 + wave2 * 0.7 + wave3 * 0.5) / 2.2;
    
    // Sharp caustic lines
    float caustic = smoothstep(-0.2, 0.6, combined);
    caustic = pow(caustic, 2.0);
    
    return caustic;
}

// God rays calculation - ahora usa posición del mundo
float calculate_god_rays(vec3 world_pos, vec3 ray_dir, float time) {
    vec3 sun_dir = normalize(sun_direction);
    float alignment = max(0.0, dot(ray_dir, sun_dir));
    
    // Surface wave simulation for ray variation
    vec3 surface_offset = vec3(
        sin(world_pos.x * 0.05 + time * 0.8),
        0.0,
        cos(world_pos.z * 0.05 + time * 0.6)
    ) * 2.0;
    
    float wave_caustics = caustics_pattern(world_pos + surface_offset, time);
    
    // Volumetric god rays with falloff
    float god_ray = pow(alignment, 8.0) * wave_caustics;
    
    return god_ray * god_rays_intensity;
}

// Enhanced density function with realistic underwater effects - CORREGIDA
float get_density_realistic(vec3 pos_viewspace, vec3 center_viewspace, vec3 world_pos, vec3 world_center, float time) {
    float dist_to_center = length(pos_viewspace - center_viewspace);
    
    if (dist_to_center > u_sphere_radius) {
        return 0.0;
    }
    
    // Base density
    float base_density = fog_density;
    
    // Depth-based effects - usando coordenadas del mundo para consistencia
    float depth_from_surface = abs(world_pos.y - world_center.y);
    float normalized_depth = depth_from_surface / u_sphere_radius;
    
    // IMPORTANTE: Usar world_pos en lugar de pos para todas las partículas
    vec3 particle_pos = world_pos * noise_scale * 0.5;
    
    // Slow-moving sediments - ahora en espacio del mundo
    vec3 sediment_flow = vec3(
        sin(time * current_speed * 0.1 + world_pos.z * 0.01),
        sin(time * current_speed * 0.05) * 0.5,
        cos(time * current_speed * 0.12 + world_pos.x * 0.01)
    ) * 10.0;
    
    float sediments = fbm(particle_pos + sediment_flow, time, 2) * particle_density;
    
    // Plankton - usando world_pos
    float plankton = noise3D(world_pos * noise_scale * 2.0 + vec3(time * noise_speed * 2.0, 0.0, 0.0)) * particle_density * 0.3;
    
    // Marine snow - usando world_pos
    float marine_snow = noise3D(world_pos * noise_scale * 0.3 + vec3(0, time * 0.1, 0)) * particle_density * 0.2;
    
    // Bottom turbidity
    float bottom_factor = smoothstep(0.7, 1.0, normalized_depth);
    float bottom_turbidity = bottom_factor * 0.5;
    
    // Thermoclines
    float thermocline = sin(normalized_depth * 12.0) * 0.1 * turbulence_strength;
    
    // Ocean currents - usando world_pos
    vec3 current_offset = vec3(
        sin(time * current_speed * 0.2 + world_pos.z * 0.005),
        sin(time * current_speed * 0.15 + world_pos.x * 0.003) * 0.3,
        cos(time * current_speed * 0.25 + world_pos.x * 0.007)
    ) * 15.0;
    
    float turbulence = fbm((world_pos + current_offset) * 0.3, time, 3) * turbulence_strength * 0.2;
    
    // Combine all effects
    base_density *= (1.0 + sediments + plankton + marine_snow + bottom_turbidity + thermocline + turbulence);
    
    // Edge softening - usando distancia en espacio de vista para correcta atenuación
    if (edge_softness > 0.01) {
        float edge_fade = 1.0 - smoothstep(
            u_sphere_radius * (1.0 - edge_softness), 
            u_sphere_radius, 
            dist_to_center
        );
        base_density *= edge_fade;
    }
    
    return max(0.0, base_density);
}

// Enhanced underwater color calculation - CORREGIDA
vec3 get_underwater_color(vec3 pos_viewspace, vec3 center_viewspace, vec3 world_pos, vec3 world_center, vec3 ray_dir, float distance_traveled, float time) {
    vec3 base_color = water_tint;
    
    // Spectral absorption
    vec3 spectral = spectral_absorption(distance_traveled);
    base_color *= spectral;
    
    // Depth-based color shift - usando coordenadas del mundo
    float depth_factor = length(world_pos - world_center) / u_sphere_radius;
    depth_factor = pow(depth_factor, 0.7);
    
    // Color shifts with depth
    vec3 surface_tint = vec3(0.8, 0.95, 1.0);
    vec3 mid_tint = vec3(0.3, 0.2, 0.95);
    vec3 deep_tint = vec3(0.2, 0.5, 0.8);
    vec3 abyss_tint = vec3(0.1, 0.3, 0.6);
    
    vec3 depth_color;
    if (depth_factor < 0.3) {
        depth_color = mix(surface_tint, mid_tint, depth_factor / 0.3);
    } else if (depth_factor < 0.7) {
        depth_color = mix(mid_tint, deep_tint, (depth_factor - 0.3) / 0.4);
    } else {
        depth_color = mix(deep_tint, abyss_tint, (depth_factor - 0.7) / 0.3);
    }
    
    base_color *= mix(vec3(1.0), depth_color, depth_color_shift);
    
    // God rays and caustics - usando world_pos
    float god_rays = calculate_god_rays(world_pos, ray_dir, time);
    
    // Caustics effects
    float caustics = 0.0;
    if (caustics_strength > 0.01 && depth_factor < 0.8) {
        float caustic_fade = 1.0 - smoothstep(0.3, 0.8, depth_factor);
        caustics = caustics_pattern(world_pos, time) * caustics_strength * caustic_fade;
    }
    
    // Add lighting effects
    vec3 light_color = vec3(0.9, 0.95, 1.0);
    base_color += light_color * god_rays * 0.4;
    base_color += light_color * caustics * 0.3;
    
    // Subtle ambient lighting variation - usando world_pos
    float ambient_variation = (noise3D(world_pos * 0.1 + vec3(time * 0.05)) * 0.5 + 0.5) * 0.1;
    base_color *= (1.0 + ambient_variation);
    
    return base_color;
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

void vertex() {
    POSITION = vec4(VERTEX.xy, 1.0, 1.0);
    
    vec4 world_center = MODEL_MATRIX * vec4(0, 0, 0, 1);
    v_volume_center_viewspace = (VIEW_MATRIX * world_center).xyz;
    
    v_inv_view_matrix = INV_VIEW_MATRIX;
    
    v_ray_origin = vec3(0.0, 0.0, 0.0);
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
    
    // Ray direction calculation
    vec3 ray_dir = v_ray_dir;
   	ray_dir = normalize(view_coords.xyz);
    
    // Ray-sphere intersection
    vec2 t_range = ray_sphere(v_volume_center_viewspace, u_sphere_radius, v_ray_origin, ray_dir);
    
    if (t_range.x > t_range.y || t_range.y < 0.0) {
        discard;
    }
    
    // Determine raymarch range
    float t_start = max(t_range.x, 0.0);
    float t_end = min(t_range.y, linear_depth);
    
    // Check if camera is inside volume
    bool is_inside = length(v_volume_center_viewspace) < u_sphere_radius;
    if (is_inside) {
        t_start = 0.0;
        t_end = min(t_range.y, linear_depth);
    }
    
    // Calcular el centro del volumen en espacio del mundo
    vec4 world_center = MODEL_MATRIX * vec4(0, 0, 0, 1);
    vec3 world_center_pos = world_center.xyz;
    
    // Raymarch through volume
    float transmittance = 1.0;
    vec3 accumulated_color = vec3(0.0);
    float accumulated_alpha = 0.0;
    
    float actual_step = (t_end - t_start) / float(max_steps);
    float t = t_start;
    float distance_traveled = 0.0;
    
    for (int i = 0; i < max_steps && t < t_end; i++) {
        vec3 pos_viewspace = v_ray_origin + ray_dir * t;
        
        // Convertir posición de espacio de vista a espacio del mundo
        vec4 world_pos4 = v_inv_view_matrix * vec4(pos_viewspace, 1.0);
        vec3 world_pos = world_pos4.xyz;
        
        // Pasar ambas posiciones a las funciones
        float density = get_density_realistic(pos_viewspace, v_volume_center_viewspace, world_pos, world_center_pos, TIME);
        
        if (density > 0.001) {
            // Calculate realistic underwater color at this position
            vec3 step_color = get_underwater_color(pos_viewspace, v_volume_center_viewspace, world_pos, world_center_pos, ray_dir, distance_traveled, TIME);
            
            // Apply density-based scattering
            step_color *= density * scattering;
            
            // Volumetric integration
            float extinction = density * (absorption + scattering) * actual_step;
            float step_transmittance = exp(-extinction);
            
            // Accumulate color and alpha
            accumulated_color += step_color * transmittance * actual_step;
            transmittance *= step_transmittance;
            accumulated_alpha += (1.0 - step_transmittance) * (1.0 - accumulated_alpha);
        }
        
        t += actual_step;
        distance_traveled += actual_step;
        
        // Early exit for performance
        if (transmittance < 0.01) break;
    }
    
    // Output final color
    ALBEDO = accumulated_color;
    ALPHA = clamp(accumulated_alpha, 0.0, 0.95);
    EMISSION = accumulated_color * emission_strength;
}