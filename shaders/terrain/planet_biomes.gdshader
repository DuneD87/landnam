shader_type spatial;
render_mode blend_mix;
#include "res://shaders/terrain/terrain_utils.gdshaderinc"
#include "res://shaders/terrain/virtual_texturing.gdshaderinc"

// Escala en 1/metros: 0.006 => manchas de ~170 m, que es lo que rompe una ladera entera.
// Estaba en 0.15 (rasgos de ~7 m): a distancia se promediaba a cero y de cerca solo
// anadia ruido por pixel.
uniform float macro_variation_scale : hint_range(0.0, 0.03) = 0.006;
uniform float macro_variation_strength : hint_range(0.0, 0.5) = 0.18;
uniform float macro_variation_contrast : hint_range(0.5, 3.0) = 1.4;

uniform bool detail_blend_enabled = true;
uniform float detail_scale_multiplier : hint_range(2.0, 16.0) = 5.7;  // primo o irracional, NO 4.0 ni 8.0
uniform float detail_blend_weight : hint_range(0.0, 1.0) = 0.5;

uniform int u_transition_mask;
uniform float radius = 5000.0;
uniform vec3 center;
// Origen flotante: desplazamiento global del mundo (igual para todos los bloques y
// planetas). 'center' es CANÓNICO fijo (set una vez); el centro real desplazado es
// (center - u_world_offset). Necesario porque el material del terreno se copia por
// bloque y un set_shader_parameter no actualizaría los bloques ya mallados.
global uniform vec3 u_world_offset;
uniform float water_radius = 29960;
uniform int has_water = 0;
#define MAX_TEXTURES 8
#define MAX_BIOMES 8 // máximo seguro (ajustable si necesitas más)
#define MAX_HEIGHTS 24
#define MAX_LATITUDE_RANGES 9
uniform sampler2D textures[MAX_TEXTURES]: source_color;
uniform sampler2D normal_textures[MAX_TEXTURES];
uniform sampler2D roughness_textures[MAX_TEXTURES];
uniform sampler2D ao_textures[MAX_TEXTURES];
uniform sampler2D height_textures[MAX_TEXTURES];

uniform float max_heights[MAX_HEIGHTS]; // 3 alturas por bioma
uniform int biome_count = 6;
uniform int textures_per_biome = 3;
uniform float biome_latitude_ranges[MAX_LATITUDE_RANGES]; // n+1 rangos para n biomas
uniform int biome_texture_indices[MAX_HEIGHTS];   // índices por bioma
uniform int biome_noise_enabled[MAX_BIOMES];
uniform int biome_noise_source_texture_indices[MAX_BIOMES];
uniform int biome_noise_target_texture_indices[MAX_BIOMES];
uniform float biome_noise_scales[MAX_BIOMES];
uniform float biome_noise_thresholds[MAX_BIOMES];
uniform float biome_noise_smoothness[MAX_BIOMES];
uniform float biome_noise_seeds[MAX_BIOMES];
uniform int biome_noise_invert[MAX_BIOMES];
uniform float biome_noise_abs_latitude_mins[MAX_BIOMES];
uniform float biome_noise_abs_latitude_maxs[MAX_BIOMES];
uniform float biome_noise_latitude_smoothness[MAX_BIOMES];
uniform sampler2D slope_texture;
uniform sampler2D slope_normal_texture;
uniform sampler2D slope_roughness_texture;
uniform sampler2D slope_height_texture;
uniform sampler2D slope_ao_texture;
uniform float slope_threshold = 0.5;
uniform float slope_smoothness = 0.5;

// Escollos de la costa. La roca de la rompiente no puede llevar la arena de la playa que tiene al
// lado, y en la franja del mar todos los biomas caen en su banda de altura más baja, que es
// justo la arena. La máscara es "cerca del nivel del mar Y en pendiente": un arrecife sale
// empinado y la orilla llana no, así que la playa se queda como está sin tener que distinguirla.
uniform sampler2D reef_texture;
uniform sampler2D reef_normal_texture;
uniform sampler2D reef_roughness_texture;
uniform sampler2D reef_ao_texture;
uniform int reef_enabled = 0;
// Alturas sobre el nivel del mar entre las que la roca de arrecife manda. El ancho del contacto NO
// es un valor propio: son transition_smoothness y el ruido de transition_height, los mismos que
// reparten las bandas de altura de los biomas, para que el borde se lea igual que los demás.
uniform float reef_band_low = -50.0;
uniform float reef_band_high = 18.0;
// Pendiente a partir de la cual cuenta como arrecife. Se mide con el mismo 'slope' que la roca.
uniform float reef_slope_threshold = 0.10;
uniform float reef_slope_softness = 0.14;
// Mezcla por height map en el contacto pendiente<->bioma. 0 = degradado lineal por angulo
// (comportamiento anterior). Con >0 la roca gana donde su height map sobresale y pierde en
// los huecos, asi que el borde se interdigita en vez de ser un aerografo.
// sharpness: pequeno = contacto duro, grande = difuso.
uniform float slope_height_blend_strength : hint_range(0.0, 1.0) = 0.0;
uniform float slope_height_blend_sharpness : hint_range(0.02, 1.0) = 0.2;
// Ruptura de la isolinea de pendiente: perturba el angulo con ruido world-space antes del
// smoothstep. Sin esto el contacto roca<->bioma es una cinta a pendiente constante que
// rodea el cerro, que es lo que se lee como "pintado". La perturbacion va ventaneada a la
// zona de contacto, asi que llanuras y cortados quedan intactos. 0 = comportamiento anterior.
uniform float slope_breakup_scale : hint_range(0.0, 0.2) = 0.025;
uniform float slope_breakup_strength : hint_range(0.0, 0.5) = 0.0;
// Comprime el eje gravitatorio en la entrada del ruido: manchas alargadas ladera abajo,
// como suelo lavado por el agua. 1 = isotropo.
uniform float slope_breakup_anisotropy : hint_range(1.0, 6.0) = 2.5;
// Estratos: el umbral de roca sube y baja en bandas horizontales de altitud, asi que la
// roca sale en repisas continuas con una causa legible en vez de motas repartidas por la
// ladera. thickness = metros por banda; warp ondula las bandas para que no sean anillos
// perfectos alrededor del planeta. 0 = off.
uniform float slope_strata_thickness : hint_range(2.0, 120.0) = 18.0;
uniform float slope_strata_strength : hint_range(0.0, 0.4) = 0.0;
uniform float slope_strata_warp : hint_range(0.0, 1.0) = 0.35;
// 0=off, 1=mascara de pendiente (rojo=slope puro), 2=angulo crudo en grados/90,
// 3=roughness final. Para tunear slope_threshold/smoothness viendo lo que decide.
uniform int debug_slope_view : hint_range(0, 3) = 0;
// Vista del factor de brillo que aplica el detail blend, sin luz: gris medio = neutro (1.0),
// mas oscuro = oscurece la textura, mas claro = la aclara. Para tunear detail_blend_weight.
uniform bool debug_detail_blend_view = false;
uniform float transition_smoothness = 0.5;

uniform float biome_transition_smoothness = 1.0;
uniform float noise_strength = 1.0;
uniform float noise_scale = 0.5;
uniform float height_transition_noise_scale : hint_range(0.0, 0.2) = 0.035;
uniform float height_transition_noise_strength : hint_range(0.0, 200.0) = 35.0;
uniform float height_blend_strength : hint_range(0.0, 1.0) = 0.45;
uniform float height_blend_contrast : hint_range(0.25, 4.0) = 1.8;
uniform float texture_scale = 0.5;
uniform float normal_strength : hint_range(0.0, 4.0) = 1.0;

uniform bool parallax_enabled = false;
uniform float parallax_strength : hint_range(0.0, 3.0) = 0.09;
uniform float parallax_height_center : hint_range(0.0, 1.0) = 0.5;
uniform float parallax_height_contrast : hint_range(0.1, 4.0) = 1.0;
uniform float parallax_min_view_dot : hint_range(0.05, 0.75) = 0.28;
uniform float parallax_max_distance = 10.0;
uniform float parallax_fade_start = 5.0;

uniform float direct_ao_strength : hint_range(0.0, 1.0) = 0.35;
// AO de las texturas sobre el ambiente de cielo. Con el ambiente plano de antes (0.05) daba igual;
// ahora que el cielo rellena las sombras, sin esto las grietas y rincones quedan planos.
uniform float ambient_ao_strength : hint_range(0.0, 1.0) = 0.85;
uniform float specular_ao_strength : hint_range(0.0, 1.0) = 0.65;
uniform float terrain_specular_strength : hint_range(0.0, 1.0) = 0.12;
uniform float water_light_depth = 1000.0;
uniform float planet_shadow_softness : hint_range(0.0, 0.2) = 0.015;
uniform float specular_aa_strength : hint_range(0.0, 4.0) = 4.0;

uniform float sun_shadow_opacity : hint_range(0.0, 1.0) = 0.7;

// --- Clima (modulado por WeatherController) ---
// Nieve POR FRAGMENTO: cada punto decide cuánta nieve cuaja según SU latitud y altitud
// (línea de nieve). weather_snow_coverage es solo la intensidad global del clima de
// nieve (0 = sin nevada). Así nievan polos y montañas, no el planeta entero.
uniform float weather_snow_coverage : hint_range(0.0, 1.0) = 0.0;
uniform vec3 weather_snow_color : source_color = vec3(0.92, 0.94, 1.0);
// Línea de nieve por latitud absoluta (grados) y por altitud (m sobre el radio base).
uniform float weather_snow_latitude_start = 35.0;
uniform float weather_snow_latitude_full = 55.0;
uniform float weather_snow_altitude_start = 1500.0;
uniform float weather_snow_altitude_full = 3500.0;

varying vec3 world_pos;
varying float height;
varying float v_fragment_ao;
varying vec3 v_planet_up_view;
varying float v_surface_radius;

varying vec3 v_normal_model;
varying vec3 v_vertex_pos_model;
varying float v_caustics;

// Datos de texturing 4-blend del mesher (CUSTOM1): 4 índices + 4 pesos por vértice.
// El ore lo escribe el VoxelGraph (nodos Spots3D -> OutputWeight); aquí solo lo leemos.
varying vec4 v_ore_indices;
varying vec4 v_ore_weights;

#define MAX_ORE_TYPES 8
uniform int ore_count = 0;
uniform sampler2D ore_albedo_textures[MAX_ORE_TYPES] : source_color;
uniform sampler2D ore_normal_textures[MAX_ORE_TYPES];
uniform sampler2D ore_roughness_textures[MAX_ORE_TYPES];

vec4 decode_8bit_vec4(float v) {
	uint i = floatBitsToUint(v);
	return vec4(
		float(i & uint(0xff)),
		float((i >> uint(8)) & uint(0xff)),
		float((i >> uint(16)) & uint(0xff)),
		float((i >> uint(24)) & uint(0xff)));
}

// Gate por latitud absoluta (grados) del override de ruido de un bioma.
float biome_noise_lat_gate(int b, float latitude) {
    float abs_lat = abs(latitude);
    float s = max(biome_noise_latitude_smoothness[b], 0.0001);
    return smoothstep(biome_noise_abs_latitude_mins[b] - s, biome_noise_abs_latitude_mins[b] + s, abs_lat)
         * (1.0 - smoothstep(biome_noise_abs_latitude_maxs[b] - s, biome_noise_abs_latitude_maxs[b] + s, abs_lat));
}

// Mascara del override: replica el ruido ridged del grafo de densidad de vegetacion
// (ZN_FastNoiseLite, 6 octavas, lacunarity 6, gain 0.1) para pintar tierra donde ese mismo
// ruido deja el terreno sin plantas. 1 = textura de destino, 0 = textura de origen.
float biome_noise_mask(vec3 planet_pos, int b) {
    int biome_seed = int(round(biome_noise_seeds[b]));
    float base_scale = biome_noise_scales[b]; // 1/period del nodo FastNoise3D del grafo
    float n      = 0.0;
    float amp    = 1.0;
    float fscale = base_scale;
    float norm   = 0.0;
    for (int o = 0; o < 6; o++) {
        float v = abs(fast_noise_lite_open_simplex2_3d(planet_pos, fscale, biome_seed + o));
        n      += (v * -2.0 + 1.0) * amp;
        norm   += amp;
        amp    *= 0.1;
        fscale *= 6.0;
    }
    n = (n / norm) * 0.5 + 0.5; // [0,1]

    float t = biome_noise_thresholds[b];
    float s = max(biome_noise_smoothness[b], 0.0001);
    float mask = smoothstep(t - s, t + s, n);
    if (biome_noise_invert[b] != 0) {
        mask = 1.0 - mask;
    }
    return mask;
}

void vertex() {
	int i = 0;
	v_vertex_pos_model = VERTEX; // posición original antes de transvoxel — el atlas fue bakeado con estas coords
	VERTEX = get_transvoxel_position(VERTEX, CUSTOM0, u_transition_mask);
	v_normal_model = NORMAL;

	// INDICES crudos (0..15 por slot); WEIGHTS normalizados a [0,1].
	v_ore_indices = decode_8bit_vec4(CUSTOM1.x);
	v_ore_weights = decode_8bit_vec4(CUSTOM1.y) / 255.0;

	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	height = length(world_pos - (center - u_world_offset)) - radius;
}

void fragment() {
#ifdef LOD_FADE_ENABLED
    // 0) Fundido de LOD: el bloque que se va y el que llega se reparten los pixeles con
    // un patron ordenado, asi que el salto de LOD se difumina en vez de aparecer de golpe.
    // Va lo primero para no muestrear texturas de un pixel que se descarta.
    if (debug_lod_fade == 0 && lod_fade_discards(FRAGCOORD.xy)) {
        discard;
    }
#endif

    // 1) Normal del voxel (detail normal map del atlas, con fallback a geometría)
    vec3 normal_model = safe_normalize(v_normal_model, vec3(0.0, 1.0, 0.0));
    get_voxel_normal_view_model(
        v_vertex_pos_model, NORMAL,
        VIEW_MATRIX * MODEL_MATRIX,
        v_normal_model, normal_model
    );
    normal_model = safe_normalize(normal_model, v_normal_model);
    vec3 normal_world = safe_normalize((MODEL_MATRIX * vec4(normal_model, 0.0)).xyz, vec3(0.0, 1.0, 0.0));
    vec3 planet_pos = world_pos - (center - u_world_offset);
	float distance_to_center = length(planet_pos);
    float underwater = (has_water != 0 && distance_to_center < water_radius) ? 1.0 : 0.0;
    vec3 planet_up = safe_normalize(planet_pos, normal_world);
    v_planet_up_view = safe_normalize((VIEW_MATRIX * vec4(planet_up, 0.0)).xyz, NORMAL);
    v_surface_radius = max(radius + height, radius + 0.001);

    // 2) Parallax opcional. Si esta apagado, no se calcula vista/distancia ni se muestrean height maps para desplazar UVs.
    bool use_parallax = parallax_enabled && parallax_strength > 0.0001 && underwater < 0.5;
    vec3 view_world = normal_world;
    float effective_height = 0.0;
    if (use_parallax) {
        vec3 camera_delta = CAMERA_POSITION_WORLD - world_pos;
        view_world = safe_normalize(camera_delta, normal_world);
        float dist = length(camera_delta);
        float parallax_fade = 1.0 - smoothstep(parallax_fade_start, parallax_max_distance, dist);
        effective_height = parallax_strength * parallax_fade;
        use_parallax = effective_height > 0.00001;
    }

    // 3) Variables de mezcla
    float noise_value = signed_fbm(planet_pos * noise_scale) * noise_strength;
    float transition_noise_active = step(0.0001, height_transition_noise_scale) * height_transition_noise_strength;
    float transition_noise = signed_fbm(planet_pos * height_transition_noise_scale) * transition_noise_active;
    float adjusted_height = height + noise_value;
    float transition_height = adjusted_height + transition_noise;

    // La pendiente se mide con la normal GEOMETRICA del mesh, no con la de la virtual
    // texture: esa ultima es detalle por celda bakeado del SDF fino, y dentro de una pared
    // hay celdas cuya normal apunta hacia arriba -> parches de bioma en mitad de la ladera.
    // Ademas cambia con el LOD, asi que el reparto roca/bioma bailaba al acercarse.
    vec3 geometry_normal_world = safe_normalize(
        (MODEL_MATRIX * vec4(safe_normalize(v_normal_model, vec3(0.0, 1.0, 0.0)), 0.0)).xyz,
        planet_up);
    float slope_cos = clamp(dot(geometry_normal_world, planet_up), -1.0, 1.0);
    float slope = 1.0 - slope_cos;
    // El umbral efectivo lo mueven los estratos; el breakup se ventanea contra ese umbral
    // ya movido, si no la ruptura del borde se descuelga de la repisa que esta dibujando.
    float slope_thr = slope_threshold;
    if (slope_strata_strength > 0.0001) {
        // Altitud por fragmento, no el varying 'height': ese se interpola entre vertices y
        // en LOD lejano estan mas separados que el grosor de una banda.
        float strata_h = (distance_to_center - radius) + signed_fbm(planet_pos * 0.004)
            * slope_strata_thickness * slope_strata_warp * 4.0;
        float f = 6.28318530718 / max(slope_strata_thickness, 0.1);
        float bands = sin(strata_h * f) * 0.6 + sin(strata_h * f * 2.37 + 1.7) * 0.4;
        slope_thr -= bands * slope_strata_strength;
    }
    if (slope_breakup_strength > 0.0001) {
        float band = 1.0 - clamp(abs(slope - slope_thr)
            / max(slope_smoothness * 3.0, 0.0001), 0.0, 1.0);
        vec3 breakup_pos = planet_pos
            - planet_up * (distance_to_center * (1.0 - 1.0 / max(slope_breakup_anisotropy, 1.0)));
        float breakup = signed_fbm(breakup_pos * slope_breakup_scale) * 0.7
                      + signed_fbm(breakup_pos * slope_breakup_scale * 9.0) * 0.3;
        slope += breakup * slope_breakup_strength * band;
    }
    float slope_factor = smoothstep(slope_thr - slope_smoothness,
                                     slope_thr + slope_smoothness, slope);

    // 4) Slope con UVs base o parallax, segun el toggle. Eje de mezcla triplanar =
    // normal GEOMETRICA, no planet_up. Con planet_up la roca se proyectaba siempre en
    // cenital, y una pared vertical apenas cambia de UV al bajar por ella: la textura salia
    // estirada en vertical justo donde la roca vive. normal_world tampoco vale (viene de la
    // virtual texture y nada entre LODs); la geometrica es el mismo compromiso que ya usa la
    // mascara de pendiente unas lineas mas arriba.
	float final_tightness = 0.0;

    TriplanarUVs slope_uvs = compute_triplanar_uvs(planet_pos, texture_scale);
    if (use_parallax) {
        slope_uvs = compute_parallax_uvs_limited(
            slope_height_texture, planet_pos, normal_world, view_world,
            texture_scale, effective_height,
            parallax_height_center, parallax_height_contrast, parallax_min_view_dot
        );
    }

    vec3 slope_color = triplanar_sample_uvs(slope_texture, slope_uvs, geometry_normal_world);
    float slope_detail_factor = 1.0;
    if (detail_blend_enabled) {
        TriplanarUVs slope_uvs_detail = compute_triplanar_uvs(planet_pos, texture_scale * detail_scale_multiplier);
        slope_detail_factor = detail_blend_factor(slope_texture, slope_uvs_detail, geometry_normal_world, detail_blend_weight);
        slope_color *= slope_detail_factor;
    }
    vec4 slope_n_v    = triplanar_normal_sample_uvs_v(slope_normal_texture, slope_uvs, normal_world);
	vec3 slope_normal = slope_n_v.xyz;
    float slope_rough = triplanar_scalar_sample_uvs(slope_roughness_texture, slope_uvs, geometry_normal_world);
    float slope_ao_v  = triplanar_scalar_sample_uvs(slope_ao_texture, slope_uvs, geometry_normal_world);
    float slope_height = (slope_height_blend_strength > 0.0001)
        ? triplanar_scalar_sample_uvs(slope_height_texture, slope_uvs, geometry_normal_world)
        : 0.0;

    // 5) Pesos de bioma
    float biome_weights[MAX_BIOMES];
    for (int i = 0; i < MAX_BIOMES; i++) biome_weights[i] = 0.0;
    float latitude = degrees(asin(planet_up.y));

    for (int i = 0; i < biome_count; i++) {
        float lower = biome_latitude_ranges[i];
        float upper = biome_latitude_ranges[i + 1];
        float center_lat = (lower + upper) * 0.5;
        float range = upper - lower;
        float w = 1.0 - abs(latitude - center_lat) / (range * biome_transition_smoothness);
        biome_weights[i] = smoothstep(0.0, 1.0, clamp(w, 0.0, 1.0));
    }

    // 6) Acumulación con parallax por textura
    vec3 final_color = vec3(0.0);
    vec3 final_normal = vec3(0.0);
    float final_roughness = 0.0;
    float final_ao = 0.0;
    float total_factor = 0.0;
    // Altura media de los materiales de bioma en este fragmento; es el lado "bioma" del
    // height blend contra la pendiente. Solo se acumula si ese blend esta activo.
    float final_material_height = 0.0;
    float final_detail_factor = 0.0; // solo para debug_detail_blend_view

    for (int b = 0; b < biome_count; b++) {
        float biome_weight = biome_weights[b];
        if (biome_weight < 0.01) continue;

        int offset = b * textures_per_biome;

        for (int j = 0; j < textures_per_biome; j++) {
            int tex_index = biome_texture_indices[offset + j];

            // Calcular factor primero — si es despreciable, saltar parallax
            float factor;
            if (j == 0) {
                factor = smoothstep(-transition_smoothness, transition_smoothness,
                                     max_heights[offset + j] - transition_height);
            } else {
                float lower = max_heights[offset + j - 1];
                float upper = max_heights[offset + j];
                float s1 = smoothstep(-transition_smoothness, transition_smoothness, upper - transition_height);
                float s2 = smoothstep(-transition_smoothness, transition_smoothness, lower - transition_height);
                factor = s1 * (1.0 - s2);
            }
            factor *= (1.0 - slope_factor) * biome_weight;
            if (factor < 0.01) continue;  // si la textura no aporta, ni parallax ni muestras

            // --- Noise override: se calcula ANTES del height bias para que el split
            //     hierba/tierra no quede contaminado por el height map de la hierba.
            //     Si height_blend se aplicara antes, override_factor heredaría el bias
            //     de la hierba y luego recibiría también el de la tierra, creando
            //     cortes donde el height map de origen tiene variaciones fuertes. ---
            float base_factor = factor;   // peso pre-bias de la textura fuente
            float override_factor = 0.0;
            int override_tex_index = biome_noise_target_texture_indices[b];
            // El gate de latitud primero: fuera de su banda no se paga el fBm (6 octavas de
            // simplex por fragmento) ni las muestras triplanares del target.
            float lat_gate = biome_noise_lat_gate(b, latitude);
            if (
                biome_noise_enabled[b] != 0 &&
                lat_gate > 0.001 &&
                tex_index == biome_noise_source_texture_indices[b] &&
                override_tex_index >= 0 &&
                override_tex_index < MAX_TEXTURES &&
                override_tex_index != tex_index
            ) {
                // División limpia: el ratio hierba/tierra lo decide el noise mask,
                // sin contaminación del height map de la fuente.
                override_factor = factor * biome_noise_mask(planet_pos, b) * lat_gate;
                base_factor     = factor - override_factor;
            }

            // UVs (y parallax opcional) para la textura fuente
            TriplanarUVs uvs = compute_triplanar_uvs(planet_pos, texture_scale);
            if (use_parallax) {
                uvs = compute_parallax_uvs_limited(
                    height_textures[tex_index], planet_pos, normal_world, view_world,
                    texture_scale, effective_height,
                    parallax_height_center, parallax_height_contrast, parallax_min_view_dot
                );
            }

            // Height bias aplicado SOLO al peso de la textura fuente (no al override).
            // Así el height map de la hierba solo afecta a la hierba, y el de la tierra
            // solo afecta a la tierra (en la sección de override más abajo).
            if ((height_blend_strength > 0.0001 || slope_height_blend_strength > 0.0001) && base_factor > 0.0001) {
                float material_height = triplanar_scalar_sample_uvs(height_textures[tex_index], uvs, planet_up);
                if (height_blend_strength > 0.0001) {
                    float height_bias = mix(0.35, 1.35, pow(clamp(material_height, 0.0, 1.0), height_blend_contrast));
                    base_factor *= mix(1.0, height_bias, height_blend_strength);
                }
                final_material_height += clamp(material_height, 0.0, 1.0) * base_factor;
            }

            // planet_up como eje de mezcla triplanar: invariante al LOD y a la normal del mesh.
            vec3 c = triplanar_sample_uvs(textures[tex_index], uvs, planet_up);
			float c_detail_factor = 1.0;
			if (detail_blend_enabled) {
			    TriplanarUVs uvs_detail = compute_triplanar_uvs(planet_pos, texture_scale * detail_scale_multiplier);
			    c_detail_factor = detail_blend_factor(textures[tex_index], uvs_detail, planet_up, detail_blend_weight);
			    c *= c_detail_factor;
			}
            vec4 n_v = triplanar_normal_sample_uvs_v(normal_textures[tex_index], uvs, normal_world);

            float r = triplanar_scalar_sample_uvs(roughness_textures[tex_index], uvs, planet_up);
            float ao = triplanar_scalar_sample_uvs(ao_textures[tex_index], uvs, planet_up);

            final_color     += c * base_factor;
            final_normal    += n_v.xyz * base_factor;
			final_tightness += n_v.w   * base_factor;
            final_roughness += r * base_factor;
            final_ao        += ao * base_factor;
            total_factor    += base_factor;
            final_detail_factor += c_detail_factor * base_factor;

            if (override_factor > 0.001) {
                TriplanarUVs override_uvs = compute_triplanar_uvs(planet_pos, texture_scale);
                if (use_parallax) {
                    override_uvs = compute_parallax_uvs_limited(
                        height_textures[override_tex_index], planet_pos, normal_world, view_world,
                        texture_scale, effective_height,
                        parallax_height_center, parallax_height_contrast, parallax_min_view_dot
                    );
                }

                if (height_blend_strength > 0.0001 || slope_height_blend_strength > 0.0001) {
                    float override_height = triplanar_scalar_sample_uvs(height_textures[override_tex_index], override_uvs, planet_up);
                    if (height_blend_strength > 0.0001) {
                        float override_height_bias = mix(0.35, 1.35, pow(clamp(override_height, 0.0, 1.0), height_blend_contrast));
                        override_factor *= mix(1.0, override_height_bias, height_blend_strength);
                    }
                    final_material_height += clamp(override_height, 0.0, 1.0) * override_factor;
                }

                vec3 override_c = triplanar_sample_uvs(textures[override_tex_index], override_uvs, planet_up);
                // Mismo detail blend que la textura fuente: sin el sale plana.
                float override_detail_factor = 1.0;
                if (detail_blend_enabled) {
                    TriplanarUVs override_uvs_detail = compute_triplanar_uvs(
                        planet_pos, texture_scale * detail_scale_multiplier);
                    override_detail_factor = detail_blend_factor(textures[override_tex_index],
                        override_uvs_detail, planet_up, detail_blend_weight);
                    override_c *= override_detail_factor;
                }
                vec4 override_n_v = triplanar_normal_sample_uvs_v(normal_textures[override_tex_index], override_uvs, normal_world);
                float override_r = triplanar_scalar_sample_uvs(roughness_textures[override_tex_index], override_uvs, planet_up);
                float override_ao = triplanar_scalar_sample_uvs(ao_textures[override_tex_index], override_uvs, planet_up);

                final_color     += override_c * override_factor;
                final_normal    += override_n_v.xyz * override_factor;
			    final_tightness += override_n_v.w   * override_factor;
                final_roughness += override_r * override_factor;
                final_ao        += override_ao * override_factor;
                total_factor    += override_factor;
                final_detail_factor += override_detail_factor * override_factor;
            }
        }
    }

    // Height blend del contacto pendiente<->bioma. El peso angular actua como offset de
    // altura de cada lado (height-lerp clasico): quien sobresale mas, gana. Solo se
    // recalcula el peso de la pendiente; los de bioma ya estan acumulados y la division
    // por total_factor reparte lo que sobra, igual que hace el resto del shader.
    float slope_mix = slope_factor;
    if (slope_height_blend_strength > 0.0001) {
        float biome_height = (total_factor > 0.0001) ? (final_material_height / total_factor) : 0.5;
        float d  = max(slope_height_blend_sharpness, 0.0001);
        float ha = slope_height + slope_factor;
        float hb = biome_height + (1.0 - slope_factor);
        float m  = max(ha, hb) - d;
        float wa = max(ha - m, 0.0);
        float wb = max(hb - m, 0.0);
        slope_mix = mix(slope_factor, wa / max(wa + wb, 0.0001), slope_height_blend_strength);
    }

    // Slope contribution. tightness DEBE sumarse igual que en el bucle de biomas: si no,
    // se diluye por total_factor y la specular AA de abajo satura la roughness a 1.0 en
    // cuanto hay algo de pendiente (con specular_aa_strength=4, a partir de ~39 grados).
    final_color     += slope_color  * slope_mix;
    final_normal    += slope_normal * slope_mix;
	final_tightness += slope_n_v.w  * slope_mix;
    final_roughness += slope_rough  * slope_mix;
    final_ao        += slope_ao_v   * slope_mix;
    total_factor    += slope_mix;
    final_detail_factor += slope_detail_factor * slope_mix;

    if (total_factor > 0.0) {
        final_color     /= total_factor;
        final_detail_factor /= total_factor;
        final_normal     = apply_normal_strength(normal_world, safe_normalize(final_normal, normal_world), normal_strength);
        final_roughness /= total_factor;
        final_ao        /= total_factor;
	 	float tightness = clamp(final_tightness / total_factor, 0.0, 1.0);
	    float variance  = max(0.0, 1.0 - tightness * tightness);
	    float a2        = final_roughness * final_roughness + variance * specular_aa_strength;
	    final_roughness = clamp(sqrt(a2), 0.04, 1.0);
    } else {
        final_color = vec3(0.5);
        final_roughness = 0.5;
        final_ao = 1.0;
        final_normal = normal_world;
        final_detail_factor = 1.0;
    }

    // 6b) Escollos: se pinta ENCIMA del reparto bioma/pendiente ya normalizado, igual que hace el
    // overlay de mena justo debajo. Los muestreos van dentro del if, así que tierra adentro y en
    // mar abierto esto no cuesta nada: la banda es una franja contigua en pantalla y el branch sale
    // coherente.
    if (reef_enabled != 0 && has_water != 0) {
        // transition_height ya trae la variacion macro y el ruido de transicion de altura, y va
        // medido sobre el radio: (radius - water_radius) lo pasa a altura sobre el mar. Usarlo aqui
        // es lo que rompe el contorno; contra la altura cruda el borde sale siguiendo una isolinea.
        float reef_h = transition_height + (radius - water_radius);
        float reef_band =
            smoothstep(-transition_smoothness, transition_smoothness, reef_h - reef_band_low)
            * (1.0 - smoothstep(-transition_smoothness, transition_smoothness, reef_h - reef_band_high));
        float reef_w = reef_band * smoothstep(reef_slope_threshold,
            reef_slope_threshold + reef_slope_softness, slope);
        if (reef_w > 0.001) {
            // Eje de mezcla = normal geometrica, igual que la roca de pendiente: estas caras son
            // paredes y la proyeccion cenital las estira.
            TriplanarUVs reef_uvs = compute_triplanar_uvs(planet_pos, texture_scale);
            vec3 reef_color = triplanar_sample_uvs(reef_texture, reef_uvs, geometry_normal_world);
            vec4 reef_n_v = triplanar_normal_sample_uvs_v(reef_normal_texture, reef_uvs, normal_world);
            float reef_rough = triplanar_scalar_sample_uvs(reef_roughness_texture, reef_uvs, geometry_normal_world);
            float reef_ao_s = triplanar_scalar_sample_uvs(reef_ao_texture, reef_uvs, geometry_normal_world);
            vec3 reef_normal = apply_normal_strength(normal_world,
                safe_normalize(reef_n_v.xyz, normal_world), normal_strength);

            // Reparto lineal a proposito: el ancho y la rotura del contacto ya vienen dentro de
            // reef_w, que es como reparten entre si las bandas de altura de los biomas. Un
            // height-lerp encima (el del contacto con la pendiente) estrecha el contacto a
            // slope_height_blend_sharpness y devuelve la linea marcada.
            final_color     = mix(final_color, reef_color * final_detail_factor, reef_w);
            final_normal    = safe_normalize(mix(final_normal, reef_normal, reef_w), normal_world);
            final_roughness = mix(final_roughness, reef_rough, reef_w);
            final_ao        = mix(final_ao, reef_ao_s, reef_w);
        }
    }

    // 7) Ore overlay leído del voxel (sistema de texturing 4-blend, canal CUSTOM1).
    // El VoxelGraph (OutputWeight layer=type_id) guardó el type_id del ore en un slot de
    // INDICES y su peso en WEIGHTS. Aquí solo lo leemos: lo que se ve es exactamente lo que hay en el
    // voxel (y lo que devuelve el minado). El índice guardado es type_id (1=iron...),
    // la textura del ore es ore_*_textures[type_id - 1].
    if (ore_count > 0) {
        for (int slot = 0; slot < 4; slot++) {
            int ore_id = int(v_ore_indices[slot] + 0.5);
            if (ore_id <= 0) continue;
            int oi = ore_id - 1;
            if (oi >= ore_count) continue;

            float ore_w = clamp(v_ore_weights[slot], 0.0, 1.0);
            if (ore_w > 0.0001) {
                // Eje de mezcla = normal geometrica, igual que la roca: las vetas viven en
                // paredes y techos de cueva, donde la proyeccion cenital estira sin limite.
                TriplanarUVs ore_uvs = compute_triplanar_uvs(planet_pos, texture_scale);
                vec3 ore_color = triplanar_sample_uvs(ore_albedo_textures[oi], ore_uvs, geometry_normal_world);
                vec4 ore_n_v = triplanar_normal_sample_uvs_v(ore_normal_textures[oi], ore_uvs, normal_world);
                float ore_rough = triplanar_scalar_sample_uvs(ore_roughness_textures[oi], ore_uvs, geometry_normal_world);
                final_color = mix(final_color, ore_color, ore_w);
                final_normal = mix(final_normal, ore_n_v.xyz, ore_w);
                final_roughness = mix(final_roughness, ore_rough, ore_w);
            }
        }
    }

    // 8) Salidas
	float macro_n = signed_fbm(planet_pos * macro_variation_scale);
	macro_n = sign(macro_n) * pow(abs(macro_n), 1.0 / macro_variation_contrast);
	float macro_factor = 1.0 + macro_n * macro_variation_strength;
	final_color *= macro_factor;

	// 8.5) Clima: nieve por fragmento. Solo cuaja en terreno frío/alto (línea de nieve por
	// latitud + altitud) y en caras hacia arriba; el clima solo aporta la intensidad global.
	if (weather_snow_coverage > 0.001) {
		float up_face = clamp(dot(normal_world, planet_up), 0.0, 1.0);
		float lat_factor = smoothstep(weather_snow_latitude_start, weather_snow_latitude_full, abs(latitude));
		float alt_factor = smoothstep(weather_snow_altitude_start, weather_snow_altitude_full, height);
		float cold = lat_factor * alt_factor;
		float snow = weather_snow_coverage * cold * smoothstep(0.35, 0.8, up_face);
		final_color = mix(final_color, weather_snow_color, snow);
		final_roughness = mix(final_roughness, 0.55, snow);
		final_normal = normalize(mix(final_normal, planet_up, snow * 0.5));
	}

	// 8.6) Debug del detail blend: emisivo plano, gris medio = factor 1.0 (neutro).
	if (debug_detail_blend_view) {
		final_color = vec3(0.0);
		EMISSION = vec3(clamp(final_detail_factor * 0.5, 0.0, 1.0));
	}

	// 8.7) Debug de pendiente: emisivo plano, sin luz. Modo 1 = lo que decide el reparto
	// (rojo=roca pura, verde=bioma puro); si un parche de hierba sale rojo aqui, no lo
	// mete la pendiente sino la banda de altura (transition_height / height_blend).
	if (debug_slope_view > 0) {
		final_color = vec3(0.0);
		if (debug_slope_view == 1) {
			EMISSION = vec3(slope_mix, 1.0 - slope_mix, 0.0);
		} else if (debug_slope_view == 2) {
			EMISSION = vec3(clamp(degrees(acos(slope_cos)) / 90.0, 0.0, 1.0));
		} else {
			EMISSION = vec3(clamp(final_roughness, 0.0, 1.0));
		}
	}

#ifdef LOD_FADE_ENABLED
	// 8.8) Debug del fundido de LOD: emisivo plano, verde el bloque que aparece y rojo el
	// que desaparece, con la intensidad = progreso. Todo negro = no hay fundido en curso.
	if (debug_lod_fade > 0) {
		float fade_t = clamp(u_lod_fade.x, 0.0, 1.0);
		final_color = vec3(0.0);
		EMISSION = u_lod_fade.y > 0.5 ? vec3(0.0, fade_t, 0.0) : vec3(fade_t, 0.0, 0.0);
	}
#endif

    ALBEDO = final_color;
	NORMAL = normalize((VIEW_MATRIX * vec4(safe_normalize(final_normal, normal_world), 0.0)).xyz);
    ROUGHNESS = final_roughness;
    v_fragment_ao = mix(clamp(final_ao, 0.0, 1.0), 1.0, underwater);
    AO = mix(1.0, v_fragment_ao, ambient_ao_strength);
    AO_LIGHT_AFFECT = 0.0;
    METALLIC = 0.0;
}
void light()
{
    vec3 n = normalize(NORMAL);
    vec3 l = normalize(LIGHT);
    vec3 v = normalize(VIEW);
    float ndotl = clamp(dot(n, l), 0.0, 1.0);

    float ao = clamp(v_fragment_ao, 0.0, 1.0);
    float direct_ao = mix(1.0, ao, direct_ao_strength);
    float specular_ao = mix(1.0, ao, specular_ao_strength);

    float planet_shadow = 1.0;
    float water_light_factor = 1.0;
    float effective_attenuation = ATTENUATION;
    if (LIGHT_IS_DIRECTIONAL) {
        // El sol usa shadow_opacity < 1.0 (relleno barato para sombras de exterior: árboles,
        // items). En el terreno NO queremos esa fuga: las cuevas deben quedar 100% a oscuras.
        // Con shadow_opacity = S, ATTENUATION ∈ [1-S, 1]; remapeamos a [0,1] para recuperar la
        // sombra completa como si la opacidad fuera 1.0. (Si S=1.0 esto es identidad.)
        effective_attenuation = clamp(
            (ATTENUATION - (1.0 - sun_shadow_opacity)) / max(sun_shadow_opacity, 0.0001),
            0.0, 1.0);

        float distance_to_center = length(world_pos - (center - u_world_offset));
        if (has_water != 0 && distance_to_center < water_radius) {
            float min_distance = water_radius - water_light_depth;
            water_light_factor = smoothstep(min_distance, water_radius, distance_to_center);
        }
        float radius_ratio = clamp(radius / max(v_surface_radius, radius + 0.001), 0.0, 1.0);
        float horizon_cos = -sqrt(max(0.0, 1.0 - radius_ratio * radius_ratio));
        float light_horizon_cos = dot(normalize(v_planet_up_view), l);
        planet_shadow = smoothstep(
            horizon_cos - planet_shadow_softness,
            horizon_cos + planet_shadow_softness,
            light_horizon_cos
        );
    }

    float light_visibility = effective_attenuation * water_light_factor * planet_shadow;

    DIFFUSE_LIGHT += ndotl * light_visibility * direct_ao * LIGHT_COLOR / PI;

    vec3 h = normalize(l + v);
    float ndoth = clamp(dot(n, h), 0.0, 1.0);
    float roughness = clamp(ROUGHNESS, 0.04, 1.0);
    float spec_power = mix(96.0, 4.0, roughness);
    float specular = pow(ndoth, spec_power) * ndotl;
    specular *= light_visibility * terrain_specular_strength * SPECULAR_AMOUNT;
    specular *= specular_ao * (1.0 - roughness);

    SPECULAR_LIGHT += specular * LIGHT_COLOR;
}
