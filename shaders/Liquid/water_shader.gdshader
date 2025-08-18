shader_type spatial;
render_mode cull_back, unshaded, depth_prepass_alpha;

uniform sampler2D DEPTH_TEXTURE: hint_depth_texture, filter_linear_mipmap;
uniform sampler2D SCREEN_TEXTURE: hint_screen_texture, filter_linear_mipmap;

uniform vec3 albedo : source_color = vec3(0.0, 0.0, 1.0);
uniform vec3 albedo2 : source_color = vec3(0.0, 0.0, 1.0);
uniform float metallic : hint_range(0.0, 1.0, 0.1) = 0;
uniform float roughness : hint_range(0.0, 1.0, 0.1) = 0.02;

uniform sampler2D texture_normal;
uniform sampler2D texture_normal2;
uniform sampler2D wave;

uniform vec2 wave_direction = vec2(2.0, 0.0);
uniform vec2 wave_direction2 = vec2(0.0, 1.0);
uniform float time_scale : hint_range(0.0, 0.2, 0.001) = 0.05;
uniform float noise_scale = 5.0; 
uniform float height_scale = 0.5;

// Parámetros para romper el tiling de las normales
uniform float normal_scale1 : hint_range(0.1, 20.0) = 1.0;
uniform float normal_scale2 : hint_range(0.1, 20.0) = 2.3;
uniform float normal_scale3 : hint_range(0.1, 20.0) = 7.8;
uniform float normal_intensity : hint_range(0.0, 2.0) = 1.0;

uniform float wave_speed = 1.0;
uniform float wave_amplitude = 1.0;
uniform float wave_frequency = 1.0;

uniform vec4 color_deep : source_color;
uniform vec4 color_shallow : source_color;
uniform float beers_law = 2.0;
uniform float depth_offset = -0.75;

uniform float edge_scale = 0.01;
uniform float near = 1.0;
uniform float far = 100.0;
uniform vec3 edge_color : source_color;

// Parámetros para el fade progresivo del edge
uniform float edge_fade_distance : hint_range(0.001, 10.0) = 0.02;
uniform float edge_max_alpha : hint_range(0.0, 1.0) = 0.8;
uniform float edge_min_alpha : hint_range(0.0, 1.0) = 0.0;

uniform float view_opacity_start : hint_range(0.0, 50.0) = 5.0;
uniform float view_opacity_end : hint_range(0.0, 10000.0) = 30.0;
uniform float view_opacity_power : hint_range(0.01, 50.0) = 2.0;

uniform vec3 sky_color_horizon : source_color = vec3(0.8, 0.9, 1.0);
uniform vec3 sky_color_zenith : source_color = vec3(0.2, 0.4, 0.8);
uniform float sky_influence : hint_range(0.0, 2.0) = 1.0;
uniform float sky_fresnel_power : hint_range(0.1, 10.0) = 3.0;
uniform float sky_gradient_power : hint_range(0.1, 5.0) = 2.0;

varying vec3 world_pos;

varying float height;
varying float view_depth;

float fresnel(float amount, vec3 normal, vec3 view) {
    return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0)), amount);
}

float edge(float depth){
    depth = 1.0 - 2.0 * depth;
    return near * far / (far + depth * (near - far));
}

// Función para generar olas procedurales como fallback
float generate_wave(vec2 pos, float time) {
    float wave1 = sin(pos.x * wave_frequency + time * wave_speed) * wave_amplitude;
    float wave2 = sin(pos.y * wave_frequency * 0.7 + time * wave_speed * 0.8) * wave_amplitude * 0.5;
    float wave3 = sin((pos.x + pos.y) * wave_frequency * 0.5 + time * wave_speed * 1.2) * wave_amplitude * 0.3;
    return (wave1 + wave2 + wave3) * 0.1;
}

// NUEVA FUNCIÓN PARA CALCULAR EL COLOR DEL CIELO
vec3 calculate_sky_color(vec3 view_direction) {
    // Calcular el ángulo vertical (0 = horizonte, 1 = cénit)
    float vertical_angle = clamp(view_direction.y * 0.5 + 0.5, 0.0, 1.0);
    vertical_angle = pow(vertical_angle, sky_gradient_power);
    
    // Interpolar entre color del horizonte y del cénit
    return mix(sky_color_horizon, sky_color_zenith, vertical_angle);
}

// Función para rotar coordenadas UV
vec2 rotate_uv(vec2 uv, float angle) {
    float cos_angle = cos(angle);
    float sin_angle = sin(angle);
    mat2 rotation_matrix = mat2(vec2(cos_angle, -sin_angle), vec2(sin_angle, cos_angle));
    return rotation_matrix * uv;
}

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec2 uv_coords = world_pos.xz;
    height = texture(wave, uv_coords / noise_scale + TIME * time_scale).r;
    
    float procedural_height = generate_wave(uv_coords, TIME);
    
    float total_height = height + procedural_height;
    VERTEX += NORMAL * total_height * height_scale;
    
    vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
    view_depth = -view_pos.z;
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
    float screen_influence = 1.0 - view_distance_factor;
    
    vec3 screen_color = textureLod(SCREEN_TEXTURE, SCREEN_UV, adjusted_depth_blend * 2.5).rgb;
    vec3 depth_color = mix(color_shallow.rgb, color_deep.rgb, adjusted_depth_blend);
    
    vec3 color = mix(
        mix(screen_color * depth_color, depth_color * 0.25, adjusted_depth_blend * 0.5),
        depth_color,
        view_distance_factor * 0.8
    );
   
    float z_depth = edge(texture(DEPTH_TEXTURE, SCREEN_UV).x);
    float z_pos = edge(FRAGCOORD.z);
    float z_dif = z_depth - z_pos;
    
    vec2 time = (TIME * wave_direction) * time_scale;
    vec2 time2 = (TIME * wave_direction2) * time_scale;
    
    // Calcular las normales con múltiples muestras para romper el tiling
    vec3 normal_blend;
    if (z_dif < edge_scale) {
        // Es borde: usar normal plana sin ruido
        normal_blend = vec3(0.5, 0.5, 1.0); // Normal neutral en tangent space
    } else {
        // No es borde: aplicar múltiples muestras de normales con diferentes escalas
        vec2 base_uv = world_pos.xz;
        
        // Primera muestra: escala normal con movimiento
        vec2 uv1 = base_uv / normal_scale1 + time;
        vec3 normal1 = texture(texture_normal, uv1).rgb;
        
        // Segunda muestra: escala diferente con rotación y movimiento diferente
        vec2 uv2 = rotate_uv(base_uv / normal_scale2, 1.57) + time2 * 0.8; // 90 grados
        vec3 normal2 = texture(texture_normal2, uv2).rgb;
        
        // Tercera muestra: escala más pequeña con rotación diferente
        vec2 uv3 = rotate_uv(base_uv / normal_scale3, 0.785) + time * 1.3; // 45 grados
        vec3 normal3 = texture(texture_normal, uv3).rgb;
        
        // Mezclar las tres muestras para romper el patrón
        normal_blend = mix(
            mix(normal1, normal2, 0.5),
            normal3,
            0.3
        );
        
        // Aplicar intensidad general
        normal_blend = mix(vec3(0.5, 0.5, 1.0), normal_blend, normal_intensity);
    }
    
    float fresnel_value = fresnel(sky_fresnel_power, NORMAL, VIEW);
    vec3 surface_color = mix(albedo, albedo2, fresnel_value);
    
    vec3 reflected_view = reflect(-VIEW, NORMAL);
    vec3 sky_color = calculate_sky_color(reflected_view);
    
    // Aplicar la influencia del cielo
    vec3 sky_reflection = sky_color * sky_influence;
    
    vec3 depth_color_adj;
    
    // MODIFICACIÓN: Alpha y color progresivos hacia el borde
    if (z_dif < edge_fade_distance && distance(CAMERA_POSITION_WORLD, world_pos) < 1000.0) {
        // Calcular factor de fade basado en la distancia al borde
        float fade_factor = clamp(z_dif / edge_fade_distance, 0.0, 1.0);
        
        ALPHA = mix(edge_min_alpha, edge_max_alpha, fade_factor);
        
        vec3 blended_edge_color = mix(edge_color, color, fade_factor);
        depth_color_adj = blended_edge_color;
    } else {
        depth_color_adj = mix(color, sky_reflection, fresnel_value * 0.8);
        depth_color_adj = mix(depth_color_adj, color, adjusted_depth_blend * 0.3);
    }
    
    vec3 final_albedo = mix(surface_color + depth_color_adj, sky_reflection, fresnel_value * sky_influence * 0.5);
    
    ALBEDO = clamp(final_albedo, vec3(0.0), vec3(1.0));
    METALLIC = metallic;
    ROUGHNESS = roughness;
    NORMAL_MAP = normal_blend;
}