shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// El planeta actualiza estos uniforms a través del include compartido.
#include "res://shaders/lib/planet_lighting.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.23, 0.36, 0.21, 1.0);
uniform vec4 tip_color : source_color = vec4(0.58, 0.70, 0.42, 1.0);
// Sotobosque: hojas, tallos y pétalos comparten material con colores de vértice.
uniform bool use_vertex_color = false;
uniform float variation_value : hint_range(0.0, 0.6) = 0.09;
uniform float variation_hue : hint_range(0.0, 1.0) = 0.35;
uniform vec3 variation_cool_tint = vec3(0.88, 1.02, 1.12);
uniform vec3 variation_warm_tint = vec3(1.08, 1.0, 0.89);
uniform vec4 dry_color : source_color = vec4(0.66, 0.64, 0.39, 1.0);
uniform float dry_ratio : hint_range(0.0, 1.0) = 0.10;
uniform float dry_amount : hint_range(0.0, 1.0) = 0.18;
uniform float blade_variation : hint_range(0.0, 0.5) = 0.09;
uniform float blade_curvature : hint_range(0.0, 1.5) = 0.32;
uniform float albedo_saturation : hint_range(0.0, 2.0) = 1.0;

uniform float base_occlusion : hint_range(0.0, 1.0) = 0.38;
uniform float base_occlusion_height : hint_range(0.01, 1.0) = 0.45;
uniform vec4 ground_tint : source_color = vec4(0.20, 0.24, 0.12, 1.0);
uniform float ground_tint_amount : hint_range(0.0, 1.0) = 0.16;
uniform float diffuse_wrap : hint_range(0.0, 1.0) = 0.42;
uniform float transmission_strength : hint_range(0.0, 3.0) = 0.65;
uniform float transmission_sharpness : hint_range(1.0, 8.0) = 3.0;
uniform float transmission_wrap : hint_range(0.0, 1.0) = 0.40;
uniform vec4 transmission_color : source_color = vec4(1.0, 0.94, 0.73, 1.0);
uniform float transmission_base : hint_range(0.0, 1.0) = 0.12;
uniform float specular_strength : hint_range(0.0, 1.0) = 0.15;
uniform float specular_roughness : hint_range(0.0, 1.0) = 0.8;

uniform float grass_height : hint_range(0.05, 5.0) = 1.0;
uniform float bend_curve : hint_range(1.0, 6.0) = 2.0;
uniform vec3 wind_direction = vec3(1.0, 0.0, 0.0);
uniform float wind_speed : hint_range(0.0, 10.0) = 1.0;
uniform float wind_amplitude : hint_range(0.0, 1.0) = 0.15;
uniform float gust_scale : hint_range(0.0, 2.0) = 0.15;
uniform float gust_speed : hint_range(0.0, 5.0) = 1.0;
uniform float flutter_speed : hint_range(0.0, 20.0) = 4.0;
uniform float flutter_amount : hint_range(0.0, 1.0) = 0.12;

uniform float fade_start = 70.0;
uniform float fade_end = 100.0;
uniform float fade_in_start = 0.0;
uniform float fade_in_end = 0.0;
uniform float near_normal_strength : hint_range(0.0, 1.0) = 0.18;
uniform float distant_normal_strength : hint_range(0.0, 1.0) = 0.25;
uniform float distant_normal_start = 95.0;
uniform float distant_normal_end = 240.0;

varying float height_factor;
varying float normal_softening;
varying vec3 instance_tint;
varying float instance_dryness;
varying float instance_seed;

uint grass_hash(uint x) {
    x ^= x >> 16u;
    x *= 2146121517u;
    x ^= x >> 15u;
    x *= 2221713035u;
    return x ^ (x >> 16u);
}

float grass_rand(uint seed) {
    return float(grass_hash(seed)) * (1.0 / 4294967296.0);
}

void vertex() {
    vec3 base = MODEL_MATRIX[3].xyz;
    vec3 relative_base = base - planet_position;
    vec3 up = normalize(relative_base);
    float world_height = dot((MODEL_MATRIX * vec4(VERTEX, 0.0)).xyz, up);
    // UV2.y identifica la malla refinada. El asset suelto conserva el fallback.
    // El gradiente sigue cada hoja: tampoco cambia con la escala de la instancia.
    height_factor = UV2.y > 0.5 ? UV2.x : clamp(world_height / grass_height, 0.0, 1.0);

    // Hash entero de celdas relativas al planeta, estable al reagrupar MultiMeshes
    // y al desplazar el origen. Evita patrones repetidos de INSTANCE_ID por bloque.
    ivec3 cell = ivec3(floor(relative_base * 4.0));
    uint id = grass_hash(uint(cell.x)) ^ grass_hash(uint(cell.y) + 2654435769u)
        ^ grass_hash(uint(cell.z) + 2246822507u);
    instance_seed = grass_rand(id);
    float r_value = grass_rand(id ^ 1013904223u);
    float r_dry = grass_rand(id ^ 3266489917u);
    // Variación amplia y discreta, con detalle por mata dentro de cada zona.
    float meadow = sin(dot(relative_base, vec3(0.037, 0.021, 0.029)))
        * sin(dot(relative_base, vec3(-0.019, 0.031, 0.017)));
    float hue = clamp(0.5 + meadow * 0.35 + (instance_seed - 0.5) * 0.25, 0.0, 1.0);
    instance_tint = mix(vec3(1.0), mix(variation_cool_tint, variation_warm_tint, hue), variation_hue);
    instance_tint *= 1.0 + (r_value * 2.0 - 1.0) * variation_value + meadow * 0.055;
    instance_dryness = smoothstep(1.0 - max(dry_ratio, 0.001), 1.0, r_dry) * dry_amount;

    float camera_distance = distance(base, CAMERA_POSITION_WORLD);
    float visibility = fade_end > fade_start ? 1.0 - smoothstep(fade_start, fade_end, camera_distance) : 1.0;
    visibility *= fade_in_end > fade_in_start ? smoothstep(fade_in_start, fade_in_end, camera_distance) : 1.0;
    visibility = sqrt(visibility);
    normal_softening = mix(near_normal_strength, max(near_normal_strength, distant_normal_strength),
        smoothstep(distant_normal_start, max(distant_normal_end, distant_normal_start + 0.001), camera_distance));
    VERTEX *= visibility;
    vec3 world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

    vec3 wt = wind_direction - up * dot(wind_direction, up);
    wt /= max(length(wt), 0.0001);
    float phase = dot(relative_base, wt) * gust_scale - TIME * wind_speed * gust_speed;
    float gust = sin(phase) * 0.75 + sin(phase * 0.43 + 1.7) * 0.25;
    float flutter = sin(TIME * flutter_speed + instance_seed * TAU + UV.y * 3.0) * flutter_amount;
    float mask = pow(height_factor, bend_curve) * visibility;
    float instance_height = length(MODEL_MATRIX[1].xyz) * grass_height;
    float sway = (gust + flutter * height_factor) * wind_amplitude * wind_speed * mask * instance_height;
    vec3 world_offset = wt * sway - up * (sway * sway * 0.5 / max(instance_height, 0.001));
    // Solo transformar el vector: reconstruir posiciones de 45 km pierde precisión.
    vec3 local_offset = (inverse(MODEL_MATRIX) * vec4(world_offset, 0.0)).xyz;
    VERTEX += local_offset;
    // Aproximación de la normal deformada; sigue la flexión de la cinta.
    vec3 derivative = local_offset * bend_curve / max(height_factor * grass_height, 0.08);
    NORMAL = normalize(NORMAL - vec3(0.0, 1.0, 0.0) * dot(derivative, NORMAL) / max(1.0 + derivative.y, 0.25));

    vertex_position_global = world_vertex + world_offset;
    planet_normal = normalize(vertex_position_global - planet_position);
    float day;
    vec3 ambient;
    compute_planet_vertex_light(vertex_position_global, planet_normal, day, ambient);
    planet_day_factor = day;
}

void fragment() {
    float blade = fract(UV.y + instance_seed);
    float gradient = smoothstep(0.0, 0.90, height_factor);
    vec3 albedo = mix(base_color.rgb, tip_color.rgb, gradient);
    albedo *= 1.0 + (blade * 2.0 - 1.0) * blade_variation;
    albedo = mix(albedo, dry_color.rgb, instance_dryness * gradient);
    albedo *= instance_tint;
    float root = 1.0 - smoothstep(0.0, base_occlusion_height, height_factor);
    albedo = mix(albedo, ground_tint.rgb, root * ground_tint_amount);
    float luma = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
    ALBEDO = mix(vec3(luma), albedo, albedo_saturation);
    if (use_vertex_color) {
        ALBEDO *= COLOR.rgb;
    }
    ROUGHNESS = specular_roughness;
    SPECULAR = specular_strength;
    AO = 1.0 - root * base_occlusion;
    AO_LIGHT_AFFECT = 0.0;
    // cull_disabled ya hace el volteo de la normal del reverso en Godot.
    // Repetirlo aquí iluminaría el envés con la orientación de la cara superior.
    vec3 radial_normal = normalize((VIEW_MATRIX * vec4(planet_normal, 0.0)).xyz);
    vec3 side = cross(NORMAL, radial_normal);
    // Pliegue suave: gradiente de luz transversal, sin dibujar una raya brillante.
    NORMAL = normalize(NORMAL + side / max(length(side), 0.0001) * (UV.x - 0.5) * 2.0 * blade_curvature);
    NORMAL = normalize(mix(NORMAL, radial_normal, normal_softening));
    // Relleno del cielo una sola vez, independiente de las sombras del sol.
    // Se calcula aquí para no duplicarlo al añadir luces locales.
    float hemisphere = clamp(dot(NORMAL, radial_normal) * 0.5 + 0.5, 0.0, 1.0);
    vec3 sky_fill = mix(ambient_color_bottom.rgb, ambient_color_top.rgb, hemisphere);
    EMISSION = ALBEDO * sky_fill * ambient_intensity * AO * mix(0.015, 1.0, planet_day_factor);
}

void light() {
    float ao = mix(1.0 - base_occlusion, 1.0, smoothstep(0.0, base_occlusion_height, height_factor));
    float ndl = dot(NORMAL, LIGHT);
    // Un único difuso normalizado + transmisión, sin sumar el SSS/rim del include.
    float wrapped = max(ndl + diffuse_wrap, 0.0) / ((1.0 + diffuse_wrap) * (1.0 + diffuse_wrap));
    float toward_sun = max(dot(VIEW, -LIGHT), 0.0);
    float transmission = pow(toward_sun, transmission_sharpness)
        * mix(max(-ndl, 0.0), 1.0, transmission_wrap)
        * mix(transmission_base, 1.0, height_factor) * transmission_strength;
    float day = LIGHT_IS_DIRECTIONAL ? planet_day_factor : 1.0;
    vec3 energy = LIGHT_COLOR * ATTENUATION * day / PI;
    DIFFUSE_LIGHT += (vec3(wrapped) + transmission * transmission_color.rgb) * energy * ao;
    vec3 half_sum = LIGHT + VIEW;
    vec3 half_vector = half_sum / max(length(half_sum), 0.0001);
    float highlight = pow(max(dot(NORMAL, half_vector), 0.0), mix(64.0, 12.0, ROUGHNESS));
    SPECULAR_LIGHT += highlight * specular_strength * 0.12 * max(ndl, 0.0) * energy * ao;
}
