shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// El planeta actualiza estos uniforms a través del include compartido.
#include "res://shaders/lib/planet_lighting.gdshaderinc"
#include "res://shaders/lib/climate.gdshaderinc"
#include "res://shaders/lib/season.gdshaderinc"
#include "res://shaders/lib/blood_splats.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.23, 0.36, 0.21, 1.0);
uniform vec4 tip_color : source_color = vec4(0.58, 0.70, 0.42, 1.0);
// Sotobosque: hojas, tallos y pétalos comparten material con colores de vértice.
uniform bool use_vertex_color = false;
// Follaje con normales de volumen horneadas (hacia fuera de la copa): el envés usa
// la misma normal que la cara. Con el volteo normal, una hoja vista por detrás
// recibe una normal hacia el interior de la mata y sale casi negra.
uniform bool volume_normal_both_faces = false;
uniform float variation_value : hint_range(0.0, 0.6) = 0.09;
uniform float variation_hue : hint_range(0.0, 1.0) = 0.9;
uniform vec3 variation_cool_tint = vec3(0.82, 1.0, 0.9);
uniform vec3 variation_warm_tint = vec3(1.16, 1.05, 0.74);
uniform vec4 dry_color : source_color = vec4(0.66, 0.64, 0.39, 1.0);
uniform float dry_ratio : hint_range(0.0, 1.0) = 0.10;
uniform float dry_amount : hint_range(0.0, 1.0) = 0.18;
uniform float blade_variation : hint_range(0.0, 0.5) = 0.09;
// Manchas del prado: ruido de valor 3D sobre la posición relativa al planeta, a dos
// escalas (meadow_scale y ~0,3 de ella). Deciden el tono fresco o cálido de cada
// mata, su valor y zonas más secas, de forma continua y sin repetirse por bloque.
uniform float meadow_scale = 26.0;
uniform float meadow_value : hint_range(0.0, 0.6) = 0.3;
uniform float dry_patch_amount : hint_range(0.0, 1.0) = 0.5;
uniform float dry_patch_threshold : hint_range(0.0, 1.0) = 0.56;
// Hojas secas sueltas dentro de las matas verdes.
uniform float dead_blade_ratio : hint_range(0.0, 0.5) = 0.08;
uniform float dead_blade_amount : hint_range(0.0, 1.0) = 0.6;
// Las hojas que dobla una ráfaga enseñan su cara más clara: una onda de brillo
// recorre el prado con el viento.
uniform float wind_sheen : hint_range(0.0, 1.0) = 0.22;
uniform float blade_curvature : hint_range(0.0, 1.5) = 0.32;
uniform float albedo_saturation : hint_range(0.0, 2.0) = 1.0;

uniform float base_occlusion : hint_range(0.0, 1.0) = 0.45;
uniform float base_occlusion_height : hint_range(0.01, 1.0) = 0.5;
// Arranque del color del suelo del bioma verde (textura oliva del terreno): la hoja
// sale del suelo en vez de parecer pegada encima.
uniform vec4 ground_tint : source_color = vec4(0.25, 0.26, 0.10, 1.0);
uniform float ground_tint_amount : hint_range(0.0, 1.0) = 0.35;
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
// Morph de LOD por mata. Las hojas que no existen en el siguiente LOD se estrechan
// hasta desaparecer y las supervivientes se ensanchan, así que el instancer puede
// cambiar la malla de un bloque (por su centro) sin salto visible. Requiere mallas
// con CUSTOM0: xyz = borde respecto al eje de la hoja, w = 4 * LOD de la malla +
// último LOD en el que sigue la hoja. Sin esos datos no desplaza nada.
uniform bool lod_morph_enabled = false;
uniform vec3 lod_morph_start = vec3(10.0, 24.0, 46.0);
uniform vec3 lod_morph_end = vec3(16.0, 34.0, 62.0);
// Ensanchado por nivel: el mismo factor con el que se hornea cada LOD.
uniform float lod_width_growth : hint_range(1.0, 2.0) = 1.55;
// Semianchura mínima en píxeles: una hoja más fina que un píxel parpadea y deja
// de cubrir el suelo. El tope evita convertir una hoja lejana en una pala.
uniform float min_half_width_pixels : hint_range(0.0, 2.0) = 0.6;
uniform float max_pixel_widening : hint_range(1.0, 4.0) = 2.5;
uniform float near_normal_strength : hint_range(0.0, 1.0) = 0.18;
uniform float distant_normal_strength : hint_range(0.0, 1.0) = 0.25;
uniform float distant_normal_start = 95.0;
uniform float distant_normal_end = 240.0;

varying float height_factor;
varying float normal_softening;
varying vec3 instance_tint;
varying float instance_dryness;
varying float instance_seed;
varying float wind_shade;
// Nieve del clima frío en el sitio de la mata: x = cobertura, y = casquete.
varying vec2 v_snow_climate;
// Sangre en la hoja (BloodFoliage): x = cuánta, y = lo seca que está.
varying vec2 v_blood;
// Estación. Hierba: x = sequedad, y = verdor tierno.
// Sotobosque (hojas): x = etapa de otoño, y = hoja tierna.
varying vec4 v_season;

// Fracción de la altura de la mata que se hunde en la nieve con el suelo nevado del todo: la hierba
// asoma en matas cortas en vez de crecer encima de la nieve.
uniform float snow_burial : hint_range(0.0, 1.0) = 0.35;
// Escarcha en las puntas de las hojas donde el clima ya deja nieve (0 = sin escarcha).
uniform float snow_frost : hint_range(0.0, 1.0) = 0.35;

// Estaciones (season.gdshaderinc). La hierba sigue a la pradera: tierna en primavera, agostada en
// otoño, parda y algo acostada en invierno.
// Fracción de la altura que pierde la hierba parda del invierno.
uniform float winter_flatten : hint_range(0.0, 1.0) = 0.2;
// Sotobosque (use_vertex_color): COLOR.a marca la pieza (1 hoja, 0,75 tallo, 0,5 flor) y
// season_kind lo que hace cada especie con sus hojas: 0 nada, 1 herbácea (se agosta con la
// pradera), 2 arbusto caduco (cambia de color y pierde la hoja), 3 perenne. Las flores se abren en
// su ventana (bloom_center, bloom_width: fase local) en todas.
uniform int season_kind = 0;
uniform vec4 autumn_early : source_color = vec4(0.75, 0.68, 0.3, 1.0);
uniform vec4 autumn_late : source_color = vec4(0.62, 0.45, 0.2, 1.0);
uniform vec4 autumn_withered : source_color = vec4(0.42, 0.32, 0.2, 1.0);
// Luminancia y cromaticidad verde medias de las hojas (lineal), las de los colores de otoño.
uniform float leaf_luma_ref = 0.15;
uniform float leaf_chroma_ref = 0.5;
uniform float bloom_center = 0.14;
uniform float bloom_width = 0.32;

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

float grass_cell(ivec3 c) {
    return grass_rand(grass_hash(uint(c.x) * 73856093u ^ uint(c.y) * 19349663u ^ uint(c.z) * 83492791u));
}

// Ruido de valor 3D suavizado: ocho esquinas con hash entero.
float grass_value_noise(vec3 p) {
    vec3 cell = floor(p);
    vec3 f = p - cell;
    vec3 u = f * f * (3.0 - 2.0 * f);
    ivec3 c = ivec3(cell);
    float x00 = mix(grass_cell(c), grass_cell(c + ivec3(1, 0, 0)), u.x);
    float x10 = mix(grass_cell(c + ivec3(0, 1, 0)), grass_cell(c + ivec3(1, 1, 0)), u.x);
    float x01 = mix(grass_cell(c + ivec3(0, 0, 1)), grass_cell(c + ivec3(1, 0, 1)), u.x);
    float x11 = mix(grass_cell(c + ivec3(0, 1, 1)), grass_cell(c + ivec3(1, 1, 1)), u.x);
    return mix(mix(x00, x10, u.y), mix(x01, x11, u.y), u.z);
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
    // Manchas del prado a dos escalas, con detalle por mata dentro de cada zona.
    // El ruido de valor rara vez sale de 0,3–0,7: se estira para que las manchas se lean.
    float patch_noise = grass_value_noise(relative_base / meadow_scale);
    float detail_noise = grass_value_noise(relative_base / (meadow_scale * 0.3) + vec3(17.3, 5.1, 9.7));
    float patch = smoothstep(0.28, 0.72, patch_noise);
    float detail = smoothstep(0.28, 0.72, detail_noise);
    float hue = clamp(patch * 0.7 + detail * 0.3 + (instance_seed - 0.5) * 0.3, 0.0, 1.0);
    instance_tint = mix(vec3(1.0), mix(variation_cool_tint, variation_warm_tint, hue), variation_hue);
    instance_tint *= 1.0 + (r_value * 2.0 - 1.0) * variation_value
        + ((patch - 0.5) * 0.7 + (detail - 0.5) * 0.3) * meadow_value;
    // Las zonas secas salen del extremo cálido de las mismas manchas: el prado pasa de
    // verde a verde amarillento y a paja, sin una tercera evaluación de ruido.
    float dry_zone = smoothstep(dry_patch_threshold, dry_patch_threshold + 0.14,
        patch_noise * 0.7 + detail_noise * 0.3);
    instance_dryness = max(smoothstep(1.0 - max(dry_ratio, 0.001), 1.0, r_dry) * dry_amount,
        dry_zone * dry_patch_amount);

    // Estaciones. season_width escala la anchura de la pieza (CUSTOM0): 0 la quita (hoja caída,
    // flor cerrada).
    float season_width = 1.0;
    v_season = vec4(0.0);
    if (!use_vertex_color) {
        vec2 meadow = season_meadow_state(relative_base);
        float blade_seed = fract(UV.y + instance_seed);
        // Unas hojas se agostan antes que otras: en invierno queda alguna verde.
        float dry = clamp(meadow.x * (1.15 - 0.3 * fract(blade_seed * 5.13)), 0.0, 1.0);
        v_season = vec4(dry, meadow.y, 0.0, 0.0);
        instance_dryness *= 1.0 - meadow.y;
        VERTEX.y *= 1.0 - winter_flatten * smoothstep(0.6, 1.0, meadow.x);
    } else if (season_kind > 0) {
        if (COLOR.a < 0.625) {
            // Flor: se abre y se cierra en su ventana, cada mata a su ritmo.
            float bloom = season_bloom(relative_base, bloom_center, bloom_width);
            season_width = smoothstep(0.0, 0.35, clamp(bloom * 1.6 - instance_seed * 0.6, 0.0, 1.0));
        } else if (COLOR.a > 0.875) {
            if (season_kind == 2) {
                vec2 state = season_leaf_state(relative_base, (instance_seed - 0.5) * SEASON_TREE_JITTER, 0.0);
                vec3 card = season_card(state, fract(UV.y * 7.13 + instance_seed));
                season_width = card.x;
                v_season.xy = card.yz;
            } else if (season_kind == 1) {
                v_season.xy = season_meadow_state(relative_base);
            }
        }
    }

    // Distancia a la cámara del jugador también en el pase de sombras: con la de la
    // luz, el morph y los relevos no coincidirían entre la planta y su sombra.
    float camera_distance = distance(base, MAIN_CAM_INV_VIEW_MATRIX[3].xyz);
    float visibility = fade_end > fade_start ? 1.0 - smoothstep(fade_start, fade_end, camera_distance) : 1.0;
    visibility *= fade_in_end > fade_in_start ? smoothstep(fade_in_start, fade_in_end, camera_distance) : 1.0;
    visibility = sqrt(visibility);
    normal_softening = mix(near_normal_strength, max(near_normal_strength, distant_normal_strength),
        smoothstep(distant_normal_start, max(distant_normal_end, distant_normal_start + 0.001), camera_distance));
    if (lod_morph_enabled) {
        int packed = int(round(CUSTOM0.w));
        float mesh_lod = float(packed >> 2);
        float survival = float(packed & 3);
        vec3 morph = clamp((vec3(camera_distance) - lod_morph_start)
            / max(lod_morph_end - lod_morph_start, vec3(0.001)), 0.0, 1.0);
        // Una malla más detallada de lo necesario imita el LOD siguiente; una más
        // simple se queda como está (el bloque cambia de malla después del morph).
        float level = max(morph.x + morph.y + morph.z, mesh_lod);
        float presence = clamp(survival + 1.0 - level, 0.0, 1.0);
        float widen = pow(lod_width_growth, level - mesh_lod);
        float half_width = length(CUSTOM0.xyz) * length(MODEL_MATRIX[0].xyz) * widen;
        // La anchura mínima depende de la proyección del jugador, que el pase de
        // sombras no tiene: allí la hoja conserva su anchura de morph.
        float pixel_gain = 1.0;
        if (!IN_SHADOW_PASS) {
            float metres_per_pixel = camera_distance * 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
            pixel_gain = clamp(min_half_width_pixels * metres_per_pixel / max(half_width, 0.00001),
                1.0, max_pixel_widening);
        }
        VERTEX += CUSTOM0.xyz * (presence * widen * pixel_gain * season_width - 1.0);
    } else {
        VERTEX += CUSTOM0.xyz * (season_width - 1.0);
    }
    VERTEX *= visibility;
    // Medio enterrada en la nieve. También en el pase de sombras: si no, la sombra sería la de la
    // mata entera. En tierra templada climate_snow_coldness no evalúa ruido y esto no cuesta nada.
    float snow_cold = climate_snow_coldness(relative_base);
    v_snow_climate = vec2(climate_snow_cover(snow_cold), climate_glacier(snow_cold));
    VERTEX.y -= v_snow_climate.x * snow_burial * grass_height;
    vec3 world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    // Sangre sobre la hoja en reposo, para que vaya pegada a ella con el viento. La sombra no la usa.
    v_blood = IN_SHADOW_PASS ? vec2(0.0) : blood_amount(world_vertex);

    vec3 wt = wind_direction - up * dot(wind_direction, up);
    wt /= max(length(wt), 0.0001);
    float phase = dot(relative_base, wt) * gust_scale - TIME * wind_speed * gust_speed;
    float gust = sin(phase) * 0.75 + sin(phase * 0.43 + 1.7) * 0.25;
    float flutter = sin(TIME * flutter_speed + instance_seed * TAU + UV.y * 3.0) * flutter_amount;
    float mask = pow(height_factor, bend_curve) * visibility;
    float instance_height = length(MODEL_MATRIX[1].xyz) * grass_height;
    float sway = (gust + flutter * height_factor) * wind_amplitude * wind_speed * mask * instance_height;
    wind_shade = gust * mask * clamp(wind_speed * wind_amplitude * 3.0, 0.0, 1.0);
    vec3 world_offset = wt * sway - up * (sway * sway * 0.5 / max(instance_height, 0.001));
    // Solo transformar el vector: reconstruir posiciones de 45 km pierde precisión.
    // La base de la instancia es ortogonal con escala, así que su inversa es la
    // traspuesta dividida por la escala² de cada eje (inverse() era mucho más caro).
    vec3 local_offset = vec3(
        dot(MODEL_MATRIX[0].xyz, world_offset) / dot(MODEL_MATRIX[0].xyz, MODEL_MATRIX[0].xyz),
        dot(MODEL_MATRIX[1].xyz, world_offset) / dot(MODEL_MATRIX[1].xyz, MODEL_MATRIX[1].xyz),
        dot(MODEL_MATRIX[2].xyz, world_offset) / dot(MODEL_MATRIX[2].xyz, MODEL_MATRIX[2].xyz));
    VERTEX += local_offset;
    // Aproximación de la normal deformada; sigue la flexión de la cinta.
    vec3 derivative = local_offset * bend_curve / max(height_factor * grass_height, 0.08);
    NORMAL = normalize(NORMAL - vec3(0.0, 1.0, 0.0) * dot(derivative, NORMAL) / max(1.0 + derivative.y, 0.25));

    vertex_position_global = world_vertex + world_offset;
    planet_normal = normalize(vertex_position_global - planet_position);
}

void fragment() {
    float blade = fract(UV.y + instance_seed);
    float gradient = smoothstep(0.0, 0.90, height_factor);
    vec3 albedo = mix(base_color.rgb, tip_color.rgb, gradient);
    albedo *= 1.0 + (blade * 2.0 - 1.0) * blade_variation;
    albedo = mix(albedo, dry_color.rgb, instance_dryness * gradient);
    // Hojas secas sueltas: la semilla de la hoja y la de la mata eligen cuáles.
    float dead = step(1.0 - dead_blade_ratio, fract(blade * 7.31 + instance_seed * 3.17));
    albedo = mix(albedo, dry_color.rgb * mix(0.7, 1.05, gradient), dead * dead_blade_amount);
    albedo *= instance_tint;
    if (!use_vertex_color) {
        albedo = season_meadow_color(albedo, v_season.xy);
    }
    albedo = mix(albedo, albedo * vec3(1.22, 1.2, 1.05) + vec3(0.012, 0.014, 0.004),
        clamp(wind_shade, 0.0, 1.0) * wind_sheen);
    float root = 1.0 - smoothstep(0.0, base_occlusion_height, height_factor);
    albedo = mix(albedo, ground_tint.rgb, root * ground_tint_amount);
    float luma = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
    ALBEDO = mix(vec3(luma), albedo, albedo_saturation);
    if (use_vertex_color) {
        ALBEDO *= COLOR.rgb;
        if (season_kind > 0 && COLOR.a > 0.875 && (v_season.x > 0.0 || v_season.y > 0.0)) {
            ALBEDO = season_leaf_color(ALBEDO, vec3(1.0, v_season.x, v_season.y), autumn_early.rgb,
                autumn_late.rgb, autumn_withered.rgb, vec2(leaf_luma_ref, leaf_chroma_ref));
        }
    }
    // Nieve sobre las hojas que miran al cielo y escarcha en las puntas.
    if (v_snow_climate.x > 0.001) {
        vec3 world_n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
        float facing = abs(dot(world_n, planet_normal)) + height_factor * 0.3 - 0.1;
        float snow = climate_object_snow(v_snow_climate.x, v_snow_climate.y, facing,
            vertex_position_global - planet_position);
        float frost = v_snow_climate.x * snow_frost * smoothstep(0.3, 1.0, height_factor);
        ALBEDO = mix(ALBEDO, CLIMATE_SNOW_ALBEDO, max(snow, frost));
    }
    // Salpicada de sangre, a gotas, y mojada mientras está fresca.
    float bleed = 0.0;
    if (v_blood.x > 0.001) {
        bleed = blood_spots(UV, instance_seed, v_blood.x);
        ALBEDO = mix(ALBEDO, blood_color(v_blood.y), bleed);
    }
    ROUGHNESS = mix(specular_roughness, 0.25, bleed * (1.0 - v_blood.y));
    SPECULAR = specular_strength;
    AO = 1.0 - root * base_occlusion;
    AO_LIGHT_AFFECT = 0.0;
    // cull_disabled ya hace el volteo de la normal del reverso en Godot.
    // Repetirlo aquí iluminaría el envés con la orientación de la cara superior;
    // solo el follaje con normales de volumen lo deshace a propósito.
    if (volume_normal_both_faces && !FRONT_FACING) {
        NORMAL = -NORMAL;
    }
    vec3 radial_normal = normalize((VIEW_MATRIX * vec4(planet_normal, 0.0)).xyz);
    vec3 side = cross(NORMAL, radial_normal);
    // Pliegue suave: gradiente de luz transversal, sin dibujar una raya brillante.
    NORMAL = normalize(NORMAL + side / max(length(side), 0.0001) * (UV.x - 0.5) * 2.0 * blade_curvature);
    NORMAL = normalize(mix(NORMAL, radial_normal, normal_softening));
    // El relleno del cielo lo pone el ambiente del entorno (el cielo del observador): una sola
    // vez, con AO, independiente de las sombras y de la hora sin paleta propia.
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
    // Horizonte del planeta POR LUZ: el sol y la luna salen y se ponen cada uno por su lado.
    float day = LIGHT_IS_DIRECTIONAL
        ? planet_light_visibility(normalize((VIEW_MATRIX * vec4(planet_normal, 0.0)).xyz), LIGHT)
        : 1.0;
    vec3 energy = LIGHT_COLOR * ATTENUATION * day / PI;
    DIFFUSE_LIGHT += (vec3(wrapped) + transmission * transmission_color.rgb) * energy * ao;
    vec3 half_sum = LIGHT + VIEW;
    vec3 half_vector = half_sum / max(length(half_sum), 0.0001);
    float highlight = pow(max(dot(NORMAL, half_vector), 0.0), mix(64.0, 12.0, ROUGHNESS));
    SPECULAR_LIGHT += highlight * specular_strength * 0.12 * max(ndl, 0.0) * energy * ao;
}
