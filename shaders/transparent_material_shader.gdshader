shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

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

varying float height_ao;

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
}

void fragment() {
    vec2 base_uv = UV;
    vec4 albedo_tex = texture(texture_albedo, base_uv);
    ALBEDO = albedo_tex.rgb;
    ALPHA *= albedo_tex.a;
    ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;

    ROUGHNESS = specular_roughness;
    SPECULAR = specular_strength;
	//EMISSION = vec3(0.2, 0.5, 0.6);
    if (!FRONT_FACING) {
        NORMAL = -NORMAL;
    }

    // Dobla la normal hacia el up del planeta (en view space) para sombrear como masa
    vec3 up_view = (VIEW_MATRIX * vec4(planet_normal, 0.0)).xyz;
    NORMAL = normalize(mix(NORMAL, up_view, normal_up_bias));
}

void light() {
    // Iluminación planetaria compartida (ver planet_lighting.gdshaderinc).
    // Sin specular para conservar el look original; el difuso es equivalente.
    vec3 d, s;
    compute_planet_light(
        NORMAL, VIEW, LIGHT, LIGHT_COLOR, ATTENUATION,
        ALBEDO, METALLIC, ROUGHNESS, specular_strength, 1.0,
        planet_day_factor, planet_ambient, LIGHT_IS_DIRECTIONAL, d, s);
    DIFFUSE_LIGHT += d * mix(ao_base, 1.0, height_ao);
}