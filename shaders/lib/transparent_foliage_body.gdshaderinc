// =============================================================================
//  transparent_foliage_body.gdshaderinc
//  Cuerpo compartido del shader de follaje (hojas/twigs). Lo incluyen dos
//  shaders que SOLO difieren en el render_mode de culling:
//    - transparent_material_shader.gdshader            -> cull_disabled (volumen, LOD cercano)
//    - transparent_material_shader_singleside.gdshader -> cull_back (mitad de fill, LOD lejano)
//  Mantener la lógica aquí para que ambas variantes no se desincronicen.
// =============================================================================
#include "res://shaders/lib/planet_lighting.gdshaderinc"

uniform vec4 albedo : source_color;
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0, 0.001) = 0.8;
uniform vec3 uv1_scale = vec3(1.0, 1.0, 1.0);
uniform vec3 uv1_offset;

// Specular
uniform float specular_strength : hint_range(0.0, 1.0, 0.01) = 0.15;
uniform float specular_roughness : hint_range(0.0, 1.0, 0.01) = 0.7;

// Follaje: cuánto se dobla la normal hacia el up del planeta y oclusión en la base
uniform float normal_up_bias : hint_range(0.0, 1.0, 0.01) = 0.6;
uniform float ao_base : hint_range(0.0, 1.0, 0.01) = 0.5;

// Detalle de iluminación por distancia: la translucencia/rim (view-dependent y
// cara en ALU) se desvanece entre detail_start y detail_end. Más allá el follaje
// solo usa Lambert + ambient y se ahorra 3 pow + 1 normalize por fragmento.
uniform float detail_start : hint_range(0.0, 500.0, 1.0) = 40.0;
uniform float detail_end : hint_range(0.0, 500.0, 1.0) = 80.0;

// Debug: tinte por mesh-LOD (alpha > 0 lo activa). Lo asigna planet.gd por LOD para
// ver in-game qué LOD se usa a cada distancia. Apagar en prod.
uniform vec4 debug_lod_tint : source_color = vec4(0.0, 0.0, 0.0, 0.0);

// --- LOD por árbol: disolución de cartas por distancia ---
// Vértices que forman una carta de hoja, para agruparlos por VERTEX_ID:
// 6 = carta doblada de Proctree, 4 = quad de conífera. Si el valor no coincide con
// el baker se ven triángulos rotos (los vértices de una carta se separan).
uniform float verts_per_card : hint_range(3.0, 12.0, 1.0) = 3.0;
// Fracción de cartas que sobrevive: 1.0 cerca -> dissolve_min_keep a partir de
// dissolve_end. Poner dissolve_min_keep = 1.0 desactiva el efecto por completo.
uniform float dissolve_start = 40.0;
uniform float dissolve_end = 150.0;
uniform float dissolve_min_keep : hint_range(0.0, 1.0, 0.01) = 0.3;

varying float height_ao;
// Up del planeta en view space: señal de baja frecuencia, se calcula por vértice.
varying vec3 up_view;
// Factor de detalle de iluminación (1 cerca, 0 lejos), calculado por vértice.
varying float foliage_detail;

// Viento
uniform vec3 wind_direction = vec3(1.0, 0.0, 0.0);
uniform float wind_speed : hint_range(0.0, 10.0, 0.01) = 1.0;
uniform float wind_base_height : hint_range(-5.0, 5.0, 0.01) = 0.0;
uniform float wind_falloff : hint_range(0.1, 10.0, 0.01) = 1.0;
uniform float wind_amplitude : hint_range(0.0, 2.0, 0.001) = 0.1;
uniform float wind_frequency : hint_range(0.0, 10.0, 0.01) = 2.0;

float random(vec3 seed) {
    return fract(sin(dot(seed, vec3(12.9898, 78.233, 45.5432))) * 43758.5453);
}

void vertex() {
    // LOD por árbol. El mesh-LOD del módulo se decide por bloque del octree (hasta
    // 256 m), así que no puede dar granularidad por árbol. Aquí usamos la distancia
    // de la INSTANCIA (traslación del MODEL_MATRIX: idéntica para todos sus vértices,
    // así que la decisión no puede partir una carta por la mitad) y colapsamos cartas
    // enteras a un punto. Los triángulos degenerados los descarta el rasterizador sin
    // coste de fragmento, que es el cuello real (fill/overdraw).
    float inst_dist = distance(CAMERA_POSITION_WORLD, MODEL_MATRIX[3].xyz);
    float keep = mix(1.0, dissolve_min_keep, smoothstep(dissolve_start, dissolve_end, inst_dist));
    float card_id = floor(float(VERTEX_ID) / verts_per_card);
    if (fract(sin(card_id * 12.9898) * 43758.5453) > keep) {
        VERTEX = vec3(0.0);
    }

    UV = UV * uv1_scale.xy + uv1_offset.xy;

    // Factor de altura: 0 en la base, 1 arriba
    // Usa VERTEX.y en espacio local (asumiendo que el modelo está orientado con Y hacia arriba)
	float height_factor = 1.0 - abs(UV.y);
	height_ao = height_factor;
	height_factor = height_factor * height_factor;  // Curva suave para transición natural (opcional, queda más orgánico)
    height_factor = height_factor * height_factor;

    // Variación por vértice para que no se muevan todos igual
    float vertex_variation = random(VERTEX);

    // Oscilación: combina una onda principal con una secundaria para más naturalidad
    float wave1 = sin(TIME * wind_frequency + dot(VERTEX, vec3(0.5, 0.0, 0.3)) + vertex_variation * 6.28);
    float wave2 = sin(TIME * wind_frequency * 1.7 + vertex_variation * 3.14) * 0.5;
    float oscillation = (wave1 + wave2) * wind_amplitude;

    // Aplicar desplazamiento modulado por altura
    vec3 wind_offset = wind_direction * oscillation * wind_speed * height_factor;
    VERTEX += wind_offset;

    // Actualizar posición global DESPUÉS del desplazamiento
    vertex_position_global = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    planet_normal = normalize(vertex_position_global - planet_position);

    float day_f;
    vec3 amb;
    compute_planet_vertex_light(vertex_position_global, planet_normal, day_f, amb);
    planet_day_factor = day_f;
    planet_ambient = amb;

    // Up del planeta en view space (baja frecuencia): antes se hacía por píxel.
    up_view = (VIEW_MATRIX * vec4(planet_normal, 0.0)).xyz;

    // Detalle por distancia a cámara: gatea SSS/rim en el follaje lejano.
    float cam_dist = distance(CAMERA_POSITION_WORLD, vertex_position_global);
    foliage_detail = 1.0 - smoothstep(detail_start, detail_end, cam_dist);
}

void fragment() {
    vec2 base_uv = UV;
    vec4 albedo_tex = texture(texture_albedo, base_uv);
    ALBEDO = albedo_tex.rgb;
    ALPHA *= albedo_tex.a;
    ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;

    ROUGHNESS = specular_roughness;
    SPECULAR = specular_strength;
    // Con cull_disabled se ven las caras traseras (efecto volumétrico); hay que
    // invertirles la normal. Con cull_back esta rama es código muerto e inocuo.
    if (!FRONT_FACING) {
        NORMAL = -NORMAL;
    }
    // Dobla la normal hacia el up del planeta (interpolado desde vertex) para sombrear como masa
    NORMAL = normalize(mix(NORMAL, up_view, normal_up_bias));

    if (debug_lod_tint.a > 0.0) {
        ALBEDO = debug_lod_tint.rgb;
    }
}

void light() {
    // Iluminación planetaria compartida (ver planet_lighting.gdshaderinc).
    // Sin specular para conservar el look original; el difuso es equivalente.
    vec3 d, s;
    compute_planet_light(
        NORMAL, VIEW, LIGHT, LIGHT_COLOR, ATTENUATION,
        ALBEDO, METALLIC, ROUGHNESS, specular_strength, 1.0,
        planet_day_factor, planet_ambient, LIGHT_IS_DIRECTIONAL, foliage_detail, d, s);
    DIFFUSE_LIGHT += d * mix(ao_base, 1.0, height_ao);
}
