shader_type spatial;
render_mode depth_draw_always, cull_disabled, blend_mix;

// Parámetros del océano basados en "Seascape"
uniform float sea_height = 0.6;
uniform float sea_choppy = 4.0;
uniform float sea_speed = 0.8;
uniform float sea_freq = 0.16;
uniform int iter_geometry = 3;
uniform int iter_fragment = 5;
uniform float wave_displacement = 1.0;

// Colores del océano
uniform vec3 sea_base = vec3(0.0, 0.09, 0.18);
uniform vec3 sea_water_color = vec3(0.48, 0.54, 0.36);
uniform vec3 sky_color = vec3(0.69, 0.84, 1.0);

// Propiedades del material
uniform float roughness = 0.02;
uniform float metallic = 0.0;
uniform float transparency = 0.85;
uniform float depth_fade_distance = 50.0;
uniform float edge_fade = 2.0;

// Parámetros de reflexión y refracción
uniform float fresnel_power = 2.0;
uniform float refraction_strength = 0.1;
uniform float reflection_strength = 0.8;
uniform float ior = 1.33; // Índice de refracción del agua
uniform float chromatic_aberration = 0.02;
uniform float caustics_strength = 0.5;
uniform float caustics_scale = 2.0;

// Parámetros de costa y olas - versión realista
uniform float shore_height = 0.0; // Altura donde empieza el efecto de costa
uniform float shore_fade_distance = 6.0; // Distancia de transición de las olas
uniform float min_wave_amplitude = 0.1; // Amplitud mínima de olas en costa
uniform float shore_foam_threshold = 0.4; // Umbral para generar espuma
uniform vec3 foam_color = vec3(0.95, 0.98, 1.0); // Color de la espuma (más sutil)
uniform float foam_intensity = 1.2; // Intensidad de la espuma (más moderada)
uniform float shore_turbulence = 1.5; // Turbulencia reducida
uniform vec3 shallow_water_color = vec3(0.3, 0.6, 0.7); // Color agua poco profunda más sutil
uniform float shallow_color_blend = 0.5; // Mezcla de color más sutil

// Luz direccional
uniform vec3 light_direction = vec3(0.0, 1.0, 0.8);

// Centro del planeta para cálculos de deformación radial
uniform vec3 planet_center = vec3(0.0, 0.0, 0.0);

// Texturas para efectos avanzados
uniform sampler2D environment_map : filter_linear_mipmap;
uniform sampler2D noise_texture : filter_linear_mipmap;

varying vec3 world_position;
varying vec3 world_normal;
varying vec3 view_direction;
varying vec2 sea_uv;
varying float sea_time;
varying vec3 tangent_space_view;
varying mat3 tbn_matrix;

// Función hash mejorada
float hash(vec2 p) {
    float h = dot(p, vec2(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

// Función de ruido
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return -1.0 + 2.0 * mix(
        mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
        mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), 
        u.y
    );
}

// Función para calcular el factor de suavizado de olas basado en la altura
float calculate_shore_factor(vec3 world_pos) {
    // Calcular la altura del vértice respecto al centro del planeta
    vec3 from_center = world_pos - planet_center;
    float height = length(from_center);
    
    // Calcular la distancia a la costa basada en la altura
    float distance_to_shore = max(shore_height - height, 0.0);
    
    // Crear una curva más suave para la transición
    float normalized_distance = distance_to_shore / shore_fade_distance;
    normalized_distance = clamp(normalized_distance, 0.0, 1.0);
    
    // Usar una curva más suave para la transición (smoothstep doble)
    float shore_influence = smoothstep(0.0, 1.0, normalized_distance);
    shore_influence = smoothstep(0.0, 1.0, shore_influence);
    
    return mix(1.0, min_wave_amplitude, shore_influence);
}

// Función mejorada para calcular espuma cerca de la costa - versión orgánica
float calculate_foam_factor(vec3 world_pos, float wave_height, float time) {
    vec3 from_center = world_pos - planet_center;
    float height = length(from_center);
    
    // Generar espuma cuando estamos cerca de la costa
    float distance_to_shore = max(shore_height - height, 0.0);
    float shore_proximity = smoothstep(shore_fade_distance, 0.0, distance_to_shore);
    
    // Usar ruido orgánico en lugar de patrones sinusoidales
    vec2 foam_uv1 = world_pos.xz * 0.3 + time * 0.1;
    vec2 foam_uv2 = world_pos.xz * 0.8 - time * 0.05;
    vec2 foam_uv3 = world_pos.xz * 1.5 + time * 0.03;
    
    float noise1 = noise(foam_uv1);
    float noise2 = noise(foam_uv2) * 0.5;
    float noise3 = noise(foam_uv3) * 0.25;
    
    // Combinar diferentes escalas de ruido para textura orgánica
    float foam_texture = (noise1 + noise2 + noise3) * 0.5 + 0.5;
    
    // Combinar proximidad a la costa con la intensidad de las olas
    float wave_intensity = abs(wave_height) / sea_height;
    
    // La espuma aparece principalmente por proximidad a costa, modulada por ruido
    float foam_base = shore_proximity * 0.7; // Base de espuma en costa
    float foam_waves = shore_proximity * wave_intensity * 0.3; // Espuma por olas
    
    // Aplicar textura orgánica
    float final_foam = (foam_base + foam_waves) * foam_texture;
    
    return smoothstep(shore_foam_threshold, 1.0, final_foam);
}

// Función para calcular el color de agua poco profunda
vec3 calculate_shallow_water_color(vec3 world_pos, vec3 base_color) {
    vec3 from_center = world_pos - planet_center;
    float height = length(from_center);
    
    float distance_to_shore = max(shore_height - height, 0.0);
    float shallow_factor = smoothstep(shore_fade_distance * 0.5, 0.0, distance_to_shore);
    
    return mix(base_color, shallow_water_color, shallow_factor * shallow_color_blend);
}
float sea_octave(vec2 uv, float choppy) {
    uv += noise(uv);
    vec2 wv = 1.0 - abs(sin(uv));
    vec2 swv = abs(cos(uv));
    wv = mix(wv, swv, wv);
    return pow(1.0 - pow(wv.x * wv.y, 0.65), choppy);
}

// Función principal del mapa del mar para geometría con suavizado de costa orgánico
float sea_map(vec3 p, int iterations) {
    mat2 octave_m = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6));
    
    // Calcular factor de suavizado basado en la altura
    float shore_factor = calculate_shore_factor(p);
    
    // Calcular distancia a la costa para efectos sutiles
    vec3 from_center = p - planet_center;
    float height = length(from_center);
    float distance_to_shore = max(shore_height - height, 0.0);
    float shore_proximity = smoothstep(shore_fade_distance, 0.0, distance_to_shore);
    
    float freq = sea_freq;
    float amp = sea_height * shore_factor;
    float choppy = sea_choppy;
    vec2 uv = p.xz;
    uv.x *= 0.75;
    
    // Olas ligeramente más lentas cerca de la costa (efecto sutil)
    float coastal_time_factor = mix(1.0, 0.7, shore_proximity * 0.5);
    float coastal_time = sea_time * coastal_time_factor;
    
    float d, h = 0.0;
    for (int i = 0; i < iterations; i++) {
        d = sea_octave((uv + coastal_time) * freq, choppy);
        d += sea_octave((uv - coastal_time) * freq, choppy);
        
        h += d * amp;
        uv = octave_m * uv;
        freq *= 1.9;
        amp *= 0.22;
        
        // Reducir el choppy más suavemente cerca de la costa
        float coastal_choppy_reduction = mix(1.0, 0.3, shore_proximity * 0.7);
        choppy = mix(choppy, 1.0, 0.2) * shore_factor * coastal_choppy_reduction;
    }
    return h;
}

// Función para calcular normales del mar usando coordenadas globales absolutas
vec3 get_sea_normal(vec3 global_pos, float eps) {
    vec3 n;
    n.y = eps;
    
    float height_center = sea_map(global_pos, iter_fragment);
    float height_x = sea_map(vec3(global_pos.x + eps, global_pos.y, global_pos.z), iter_fragment);
    float height_z = sea_map(vec3(global_pos.x, global_pos.y, global_pos.z + eps), iter_fragment);
    
    n.x = height_x - height_center;
    n.z = height_z - height_center;
    
    return normalize(n);
}

// Función de Fresnel de Schlick
float fresnel_schlick(float cos_theta, float n1, float n2) {
    float r0 = pow((n1 - n2) / (n1 + n2), 2.0);
    return r0 + (1.0 - r0) * pow(1.0 - cos_theta, 5.0);
}

// Función de refracción con aberración cromática
vec3 refract_with_chromatic_aberration(vec3 incident, vec3 normal, float eta) {
    vec3 refracted_r = refract(incident, normal, eta - chromatic_aberration);
    vec3 refracted_g = refract(incident, normal, eta);
    vec3 refracted_b = refract(incident, normal, eta + chromatic_aberration);
    
    return vec3(
        length(refracted_r),
        length(refracted_g),
        length(refracted_b)
    );
}

// Función de cáusticas simplificada
float caustics(vec2 uv, float time) {
    vec2 uv1 = uv * caustics_scale + time * 0.1;
    vec2 uv2 = uv * caustics_scale * 1.3 - time * 0.15;
    
    float c1 = texture(noise_texture, uv1).r;
    float c2 = texture(noise_texture, uv2).r;
    
    return pow(c1 * c2, 2.0) * caustics_strength;
}

// Función de iluminación difusa
float diffuse(vec3 n, vec3 l, float p) {
    return pow(dot(n, l) * 0.4 + 0.6, p);
}

// Función de iluminación especular
float specular(vec3 n, vec3 l, vec3 e, float s) {
    float nrm = (s + 8.0) / (3.141592 * 8.0);
    return pow(max(dot(reflect(e, n), l), 0.0), s) * nrm;
}

// Color del cielo mejorado
vec3 get_sky_color(vec3 e) {
    e.y = (max(e.y, 0.0) * 0.8 + 0.2) * 0.8;
    return vec3(pow(1.0 - e.y, 2.0), 1.0 - e.y, 0.6 + (1.0 - e.y) * 0.4) * 1.1;
}

// Color del mar con background protection
vec3 get_sea_color(vec3 p, vec3 n, vec3 l, vec3 eye, vec3 dist, float depth_factor, float wave_height) {
    // Calcular Fresnel
    float cos_theta = max(dot(n, -eye), 0.0);
    float fresnel = fresnel_schlick(cos_theta, 1.0, ior);
    
    // Background color para evitar ver el vacío
    vec3 background_color = sea_base; // Color del océano profundo como fallback
    
    // Reflexión
    vec3 reflected_dir = reflect(eye, n);
    vec3 reflected_color = get_sky_color(reflected_dir);
    
    // Si tienes un environment map, úsalo aquí:
    // vec3 reflected_color = texture(environment_map, reflected_dir.xy * 0.5 + 0.5).rgb;
    
    // Refracción con background protection
    vec3 refracted_dir = refract(eye, n, 1.0 / ior);
    vec3 refracted_color = background_color; // Usar background como base
    
    // Solo aplicar el color del agua si tenemos una refracción válida
    if (length(refracted_dir) > 0.1) {
        refracted_color = sea_water_color;
        // Simular refracción con aberración cromática
        vec3 chromatic_refraction = refract_with_chromatic_aberration(eye, n, 1.0 / ior);
        refracted_color *= chromatic_refraction;
    }
    
    // Color base del agua con gradiente de profundidad
    vec3 shallow_color = sea_water_color * 1.2;
    vec3 deep_color = sea_base;
    vec3 water_base = mix(shallow_color, deep_color, depth_factor);
    
    // Aplicar color de agua poco profunda de forma más sutil
    water_base = calculate_shallow_water_color(p, water_base);
    
    // Calcular factor de espuma cerca de la costa (orgánico)
    float foam_factor = calculate_foam_factor(p, wave_height, sea_time);
    
    // Reducir cáusticas en zonas costeras
    vec3 from_center = p - planet_center;
    float height = length(from_center);
    float distance_to_shore = max(shore_height - height, 0.0);
    float shore_proximity = smoothstep(shore_fade_distance, 0.0, distance_to_shore);
    
    float caustics_effect = caustics(p.xz * 0.1, sea_time) * (1.0 - shore_proximity * 0.5);
    water_base += caustics_effect * vec3(0.8, 0.9, 1.0);
    
    // Componente difusa con background protection
    vec3 diffuse_component = mix(background_color, water_base, 0.8) + diffuse(n, l, 80.0) * sea_water_color * 0.3;
    
    // Combinar refracción con el color base
    refracted_color = mix(refracted_color, diffuse_component, 0.7);
    
    // Añadir espuma de forma más sutil y realista
    vec3 foam_effect = foam_color * foam_intensity;
    
    // Aplicar espuma sin variaciones artificiales
    refracted_color = mix(refracted_color, foam_effect, foam_factor);
    
    // Mezclar reflexión y refracción usando Fresnel
    float effective_fresnel = fresnel * (1.0 - foam_factor * 0.6);
    vec3 color = mix(refracted_color, reflected_color * reflection_strength, effective_fresnel);
    
    // Atenuación por distancia
    float atten = max(1.0 - dot(dist, dist) * 0.0005, 0.0);
    color += sea_water_color * (p.y - sea_height) * 0.1 * atten;
    
    // Especular reducido por espuma de forma más sutil
    float specular_strength = 1.0 - foam_factor * 0.7;
    color += specular(n, l, eye, 120.0) * 0.8 * specular_strength;
    
    return color;
}

void vertex() {
    // Obtener la posición mundial real del vértice
    vec4 world_vertex = MODEL_MATRIX * vec4(VERTEX, 1.0);
    vec3 world_pos = world_vertex.xyz;
    
    // Tiempo del mar
    sea_time = 1.0 + TIME * sea_speed;
    
    // Calcular altura del agua usando coordenadas globales absolutas
    float water_height = sea_map(world_pos, iter_geometry);
    
    // Calcular la dirección radial desde el centro del planeta
    vec3 from_center = world_pos - planet_center;
    vec3 radial_direction = normalize(from_center);
    
    // Aplicar desplazamiento radial desde el centro del planeta
    float displacement = water_height * wave_displacement * 0.01;
    
    // Desplazar en dirección radial desde el centro
    vec3 displaced_world_pos = world_pos + radial_direction * displacement;
    
    // Convertir de vuelta a espacio local
    vec4 local_pos = inverse(MODEL_MATRIX) * vec4(displaced_world_pos, 1.0);
    VERTEX = local_pos.xyz;
    
    // Calcular normal del mundo para TBN
    vec3 world_normal_base = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
    vec3 world_tangent_base = normalize((MODEL_MATRIX * vec4(TANGENT, 0.0)).xyz);
    vec3 world_binormal = cross(world_normal_base, world_tangent_base);
    
    // Matriz TBN para el espacio tangente
    tbn_matrix = mat3(world_tangent_base, world_binormal, world_normal_base);
    
    // Pasar datos al fragment shader
    world_position = displaced_world_pos;
    world_normal = world_normal_base;
    view_direction = normalize(CAMERA_POSITION_WORLD - displaced_world_pos);
    tangent_space_view = view_direction * tbn_matrix;
    sea_uv = world_pos.xz;
}

void fragment() {
    // Recalcular posición mundial original para normales consistentes
    vec3 from_center = world_position - planet_center;
    vec3 radial_dir = normalize(from_center);
    vec3 original_world_pos = world_position - radial_dir * 
                             (sea_map(world_position, iter_fragment) * wave_displacement * 0.01);
    
    // Calcular normal detallada del mar
    float eps = 0.1;
    vec3 sea_normal = get_sea_normal(original_world_pos, eps);
    
    // Normal esférica basada en la dirección desde el centro del planeta
    vec3 sphere_normal = normalize(original_world_pos - planet_center);
    vec3 final_normal = normalize(mix(sphere_normal, sea_normal, 0.8));
    
    // Transformar normal al espacio tangente para efectos avanzados
    vec3 tangent_normal = normalize(tbn_matrix * final_normal);
    
    // Calcular dirección de la luz normalizada
    vec3 light = normalize(light_direction);
    
    // Dirección del ojo (vista)
    vec3 eye_dir = -view_direction;
    
    // Calcular factor de profundidad simulada
    float wave_height = sea_map(original_world_pos, iter_fragment);
    float depth_factor = smoothstep(-sea_height, sea_height, -wave_height) * 0.8;
    
    // Distancia para efectos de atenuación
    vec3 dist = world_position - planet_center;
    
    // Obtener color del mar con efectos avanzados (incluyendo espuma de costa)
    vec3 sea_color = get_sea_color(world_position, final_normal, light, eye_dir, dist, depth_factor, wave_height);
    
    // Calcular transparencia con Fresnel mejorado y efectos de costa
    float cos_theta = max(dot(final_normal, -eye_dir), 0.0);
    float fresnel = fresnel_schlick(cos_theta, 1.0, ior);
    fresnel = pow(fresnel, fresnel_power);
    
    // Calcular factor de espuma para afectar la transparencia
    float foam_factor = calculate_foam_factor(world_position, wave_height, sea_time);
    
    // Calcular factor para evitar ver el cielo a través del agua
    vec3 view_to_camera = normalize(CAMERA_POSITION_WORLD - world_position);
    vec3 planet_normal = normalize(world_position - planet_center);
    
    // Detectar si estamos mirando hacia "afuera" del planeta
    float looking_outward = dot(view_to_camera, planet_normal);
    
    // Si estamos mirando hacia afuera y cerca del horizonte, hacer más opaco
    float horizon_factor = 1.0 - abs(dot(view_to_camera, final_normal));
    float edge_opacity = smoothstep(0.0, 0.5, horizon_factor) * smoothstep(-0.2, 0.2, looking_outward);
    
    // Factor de transparencia con protección contra ver el cielo
    float alpha = mix(transparency, 1.0, fresnel);
    alpha = mix(alpha, 1.0, depth_factor * 0.3);
    alpha = mix(alpha, 1.0, foam_factor * 0.4);
    
    // Hacer completamente opaco en los bordes problemáticos
    alpha = mix(alpha, 1.0, edge_opacity * 0.9);
    
    // Perturbación de la normal para refracción
    vec3 perturbed_normal = final_normal + tangent_normal * refraction_strength;
    perturbed_normal = normalize(perturbed_normal);
    
    // Configurar propiedades del material con alpha threshold
    ALBEDO = sea_color;
    NORMAL = perturbed_normal;
    ROUGHNESS = roughness;
    METALLIC = metallic;
    ALPHA = alpha;
    
    // Añadir alpha scissor para evitar transparencias problemáticas
    if (alpha < 0.1) {
        discard;
    }
    
    // Efectos adicionales de refracción en el mapa de normales
    NORMAL_MAP = tangent_normal * refraction_strength;
    
    // Añadir emisión sutil para cáusticas
    float emission_strength = caustics(sea_uv * 0.05, sea_time * 0.5) * 0.05;
    EMISSION = sea_color * emission_strength;
}