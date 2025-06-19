shader_type spatial;

// From Voxel Tools API
uniform int u_transition_mask;
uniform float radius = 5000;
uniform vec3 center = vec3(0.0, 0.0, 10000.0);

// Texturas y alturas configurables
#define MAX_TEXTURES 8
uniform sampler2D textures[MAX_TEXTURES]; // Arreglo de texturas de albedo
uniform sampler2D normal_textures[MAX_TEXTURES]; // Nuevo: arreglo de normal maps
uniform sampler2D roughness_textures[MAX_TEXTURES]; // Nuevo: arreglo de roughness maps
uniform float max_heights[MAX_TEXTURES]; // Alturas máximas para cada textura
uniform int texture_count = 3; // Número de texturas usadas
uniform sampler2D slope_texture; // Textura para pendientes
uniform sampler2D slope_normal_texture; // Nuevo: normal map para slope
uniform sampler2D slope_roughness_texture; // Nuevo: roughness map para slope
uniform float slope_threshold = 0.7; // Umbral de inclinación para la textura de slope
uniform float slope_smoothness = 0.2; // Suavidad de la transición del slope
uniform float transition_smoothness = 1.5; // Suavidad de las transiciones de altura
uniform float noise_strength = 1.0; // Influencia del ruido
uniform float noise_scale = 0.1; // Escala del ruido principal
uniform float noise_detail_scale = 0.5; // Escala del ruido detallado
uniform float noise_detail_strength = 0.3; // Influencia del ruido detallado
uniform float texture_scale = 0.1; // Escala para el tiling de texturas
uniform float normal_strength = 1.0; // Nuevo: fuerza del normal mapping

varying vec3 world_pos;
varying float height;
varying vec3 world_normal;
varying mat3 tbn_matrix; // Nuevo: matriz TBN para normal mapping

// Función de ruido procedural simple
float hash(vec3 p) {
    p = fract(p * 0.3183099 + 0.1);
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
    vec3 i = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f); // Interpolación suave
    return mix(
        mix(
            mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
            mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x),
            f.y
        ),
        mix(
            mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
            mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x),
            f.y
        ),
        f.z
    );
}

float get_transvoxel_secondary_factor(int idata) {
    int transition_mask = u_transition_mask & 0xff;
    int cell_border_mask = idata & 63;
    int vertex_border_mask = (idata >> 8) & 63;
    int m = transition_mask & cell_border_mask;
    float t = float(m != 0);
    t *= float((vertex_border_mask & ~transition_mask) == 0);
    return t;
}

vec3 get_transvoxel_position(vec3 vertex_pos, vec4 fdata) {
    int idata = floatBitsToInt(fdata.a);
    float secondary_factor = get_transvoxel_secondary_factor(idata);
    vec3 secondary_position = fdata.xyz;
    vec3 pos = mix(vertex_pos, secondary_position, secondary_factor);
    int itransition = (idata >> 16) & 0xff;
    float transition_cull = float(itransition == 0 || (itransition & u_transition_mask) != 0);
    pos *= transition_cull;
    return pos;
}

void vertex() {
    VERTEX = get_transvoxel_position(VERTEX, CUSTOM0);
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    height = length(world_pos - center) - radius;
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);

    // Nuevo: calcular matriz TBN para normal mapping
    vec3 tangent = normalize(cross(world_normal, vec3(0.0, 1.0, 0.01))); // Añadir pequeño offset para evitar singularidades
    vec3 bitangent = normalize(cross(world_normal, tangent));
    tbn_matrix = mat3(tangent, bitangent, world_normal);
}

// Función para muestrear texturas con mapeo triplanar
vec3 triplanar_sample(sampler2D tex, vec3 pos, vec3 normal, float scale) {
    vec2 uv_x = pos.yz * scale;
    vec2 uv_y = pos.xz * scale;
    vec2 uv_z = pos.xy * scale;
    vec3 col_x = texture(tex, uv_x).rgb;
    vec3 col_y = texture(tex, uv_y).rgb;
    vec3 col_z = texture(tex, uv_z).rgb;
    vec3 blend = pow(abs(normal), vec3(2.0)); // Aumentar contraste en la mezcla
	blend = normalize(max(blend, 0.0001));
	blend /= (blend.x + blend.y + blend.z);
    return col_x * blend.x + col_y * blend.y + col_z * blend.z;
}

// Nuevo: función para muestrear normal maps con mapeo triplanar
vec3 triplanar_normal_sample(sampler2D tex, vec3 pos, vec3 normal, float scale) {
    vec2 uv_x = pos.yz * scale;
    vec2 uv_y = pos.xz * scale;
    vec2 uv_z = pos.xy * scale;
    vec3 norm_x = texture(tex, uv_x).rgb * 2.0 - 1.0;
    vec3 norm_y = texture(tex, uv_y).rgb * 2.0 - 1.0;
    vec3 norm_z = texture(tex, uv_z).rgb * 2.0 - 1.0;

    // Ajustar normales según el plano de proyección
    norm_x = vec3(norm_x.xy + normal.zy, norm_x.z * normal.x);
    norm_y = vec3(norm_y.xy + normal.xz, norm_y.z * normal.y);
    norm_z = vec3(norm_z.xy + normal.xy, norm_z.z * normal.z);

    vec3 blend = abs(normal);
    blend = normalize(max(blend, 0.0001));
    blend /= (blend.x + blend.y + blend.z);
    vec3 final_normal = norm_x * blend.x + norm_y * blend.y + norm_z * blend.z;
    return normalize(final_normal);
}

// Nuevo: función para muestrear roughness maps con mapeo triplanar (escala de grises)
float triplanar_roughness_sample(sampler2D tex, vec3 pos, vec3 normal, float scale) {
    vec2 uv_x = pos.yz * scale;
    vec2 uv_y = pos.xz * scale;
    vec2 uv_z = pos.xy * scale;
    float rough_x = texture(tex, uv_x).r;
    float rough_y = texture(tex, uv_y).r;
    float rough_z = texture(tex, uv_z).r;
    vec3 blend = abs(normal);
    blend = normalize(max(blend, 0.0001));
    blend /= (blend.x + blend.y + blend.z);
    return rough_x * blend.x + rough_y * blend.y + rough_z * blend.z;
}

void fragment() {
    // Calcular ruido para perturbar las transiciones
    float noise_value = noise(world_pos * noise_scale) * noise_strength;
    float noise_detail = noise(world_pos * noise_detail_scale) * noise_detail_strength;
    float combined_noise = noise_value + noise_detail;
    float adjusted_height = height + combined_noise;

    // Calcular el factor de pendiente
    float slope = 1.0 - dot(world_normal, normalize(world_pos - center));
    float slope_factor = smoothstep(slope_threshold - slope_smoothness, slope_threshold + slope_smoothness, slope);

    // Muestrear texturas de slope
    vec3 slope_color = triplanar_sample(slope_texture, world_pos, world_normal, texture_scale);
    vec3 slope_normal = triplanar_normal_sample(slope_normal_texture, world_pos, world_normal, texture_scale);
    float slope_roughness = triplanar_roughness_sample(slope_roughness_texture, world_pos, world_normal, texture_scale);

    // Inicializar color, normal, rugosidad y factores de mezcla
    vec3 final_color = vec3(0.0);
    vec3 final_normal = vec3(0.0);
    float final_roughness = 0.0;
    float total_factor = 0.0;

    // Iterar sobre las texturas basadas en altura
    for (int i = 0; i < texture_count && i < MAX_TEXTURES; i++) {
        // Muestrear texturas
        vec3 tex_color = triplanar_sample(textures[i], world_pos, world_normal, texture_scale);
        vec3 tex_normal = triplanar_normal_sample(normal_textures[i], world_pos, world_normal, texture_scale);
        float tex_roughness = triplanar_roughness_sample(roughness_textures[i], world_pos, world_normal, texture_scale);

        // Calcular factor de mezcla para esta textura
        float factor = 0.0;
        if (i == 0) {
            factor = smoothstep(-transition_smoothness, transition_smoothness, max_heights[i] - adjusted_height);
        } else {
            factor = smoothstep(-transition_smoothness, transition_smoothness, max_heights[i] - adjusted_height);
            if (i > 0) {
                factor *= (1.0 - smoothstep(-transition_smoothness, transition_smoothness, max_heights[i-1] - adjusted_height));
            }
        }

        // Perturbar el factor con ruido detallado
        factor += noise_detail * 0.2;
        factor = clamp(factor, 0.0, 1.0);

        // Reducir la influencia de las texturas basadas en altura donde domina el slope
        factor *= (1.0 - slope_factor);

        // Acumular color, normal y rugosidad
        final_color += tex_color * factor;
        final_normal += tex_normal * factor;
        final_roughness += tex_roughness * factor;
        total_factor += factor;
    }

    // Añadir la contribución de la textura de slope
    final_color += slope_color * slope_factor;
    final_normal += slope_normal * slope_factor;
    final_roughness += slope_roughness * slope_factor;
    total_factor += slope_factor;

    // Normalizar los resultados
    if (total_factor > 0.0) {
        final_color /= total_factor;
        final_normal = normalize(final_normal);
        final_roughness /= total_factor;
    } else {
        final_color = vec3(0.5); // Color por defecto
        final_normal = vec3(0.0, 0.0, 1.0); // Normal por defecto
        final_roughness = 0.5; // Rugosidad por defecto
    }

    // Asignar salidas PBR
    ALBEDO = final_color;
    NORMAL_MAP = final_normal * normal_strength; // Aplicar fuerza del normal map
    ROUGHNESS = final_roughness;

    // Nuevo: activar normal mapping en Godot
    NORMAL_MAP_DEPTH = normal_strength;
}