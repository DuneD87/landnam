shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D DEPTH_TEXTURE: hint_depth_texture, filter_linear_mipmap;
uniform sampler2D SCREEN_TEXTURE: hint_screen_texture, filter_linear_mipmap;

uniform vec3 albedo : source_color = vec3(0.0, 0.0, 1.0);
uniform vec3 albedo2 : source_color = vec3(0.0, 0.0, 1.0);
uniform float metallic : hint_range(0.0, 1.0, 0.1) = 0;
uniform float roughness : hint_range(0.0, 1.0, 0.1) = 0.02;

uniform sampler2D texture_normal;
uniform sampler2D texture_normal2;
uniform sampler2D wave; // ASEGÚRATE DE ASIGNAR UNA TEXTURA DE RUIDO AQUÍ

// Parámetros de olas - ajusta estos valores para ver más deformación
uniform vec2 wave_direction = vec2(2.0, 0.0);
uniform vec2 wave_direction2 = vec2(0.0, 1.0);
uniform float time_scale : hint_range(0.0, 0.2, 0.001) = 0.05; // Aumentado para más movimiento
uniform float noise_scale = 5.0; // Reducido para olas más grandes
uniform float height_scale = 0.5; // Aumentado para más deformación visible

// Parámetros adicionales para múltiples capas de olas
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



// Parámetros para controlar la opacidad por distancia
uniform float view_opacity_start : hint_range(0.0, 50.0) = 5.0;
uniform float view_opacity_end : hint_range(0.0, 100.0) = 30.0;
uniform float view_opacity_power : hint_range(0.1, 5.0) = 2.0;

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
    
    // Calcular las normales con ruido solo si NO es borde
    vec3 normal_blend;
    if (z_dif < edge_scale) {
        // Es borde: usar normal plana sin ruido
        normal_blend = vec3(0.5, 0.5, 1.0); // Normal neutral en tangent space
    } else {
        // No es borde: aplicar ruido normal
        normal_blend = mix(
            texture(texture_normal, world_pos.xz + time).rgb,
            texture(texture_normal2, world_pos.xz + time2).rgb,
            0.5
        );
    }
    
    float fresnel = fresnel(5.0, NORMAL, VIEW);
    vec3 surface_color = mix(albedo, albedo2, fresnel);
    
    vec3 depth_color_adj;
    if (z_dif < edge_scale && distance(CAMERA_POSITION_WORLD, world_pos) < 1000.0) {
        depth_color_adj = edge_color;
    } else {
        depth_color_adj = color;
    }
    
    ALBEDO = clamp(surface_color + depth_color_adj, vec3(0.0), vec3(1.0));
    METALLIC = metallic;
    ROUGHNESS = roughness;
    NORMAL_MAP = normal_blend;
}