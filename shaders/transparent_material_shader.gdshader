shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform vec4 albedo : source_color;
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0, 0.001) = 0.8;
uniform vec3 uv1_scale = vec3(1.0, 1.0, 1.0);
uniform vec3 uv1_offset;

uniform vec3 light_direction = vec3(1.0, 0.0, 0.0);
uniform vec3 planet_position;
uniform float transition_width : hint_range(0.0, 1.0, 0.01) = 0.2;

// Iluminación
uniform float ambient_intensity : hint_range(0.0, 1.0, 0.01) = 0.15;
uniform vec4 ambient_color_top : source_color = vec4(0.6, 0.7, 1.0, 1.0);  // Color cielo
uniform vec4 ambient_color_bottom : source_color = vec4(0.2, 0.15, 0.1, 1.0); // Color suelo

// Translucencia / SSS
uniform float translucency_strength : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform vec4 translucency_color : source_color = vec4(0.8, 1.0, 0.4, 1.0); // Tinte al atravesar
uniform float translucency_power : hint_range(1.0, 8.0, 0.1) = 2.0;

// Fresnel / rim
uniform float rim_strength : hint_range(0.0, 1.0, 0.01) = 0.3;

// Specular
uniform float specular_strength : hint_range(0.0, 1.0, 0.01) = 0.15;
uniform float specular_roughness : hint_range(0.0, 1.0, 0.01) = 0.7;

// Viento
uniform vec3 wind_direction = vec3(1.0, 0.0, 0.0);
uniform float wind_speed : hint_range(0.0, 10.0, 0.01) = 1.0;
uniform float wind_base_height : hint_range(-5.0, 5.0, 0.01) = 0.0;
uniform float wind_falloff : hint_range(0.1, 10.0, 0.01) = 1.0;
uniform float wind_amplitude : hint_range(0.0, 2.0, 0.001) = 0.1;
uniform float wind_frequency : hint_range(0.0, 10.0, 0.01) = 2.0;
varying vec3 vertex_position_global;
varying vec3 planet_normal; // Normal basada en dirección desde centro del planeta

float random(vec3 seed) {
    return fract(sin(dot(seed, vec3(12.9898, 78.233, 45.5432))) * 43758.5453);
}

void vertex() {
    UV = UV * uv1_scale.xy + uv1_offset.xy;
    
    // Factor de altura: 0 en la base, 1 arriba
    // Usa VERTEX.y en espacio local (asumiendo que el modelo está orientado con Y hacia arriba)
	float height_factor = 1.0 - abs(UV.y);
	height_factor = pow(height_factor, 2.0);    // Curva suave para transición natural (opcional, queda más orgánico)
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
}

void light() {
    // === 1. Difuso estándar (Lambert) ===
    float NdotL = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
    vec3 diffuse = NdotL * ATTENUATION * LIGHT_COLOR / PI;

   // === 2. Translucencia mejorada ===
	vec3 back_light = normalize(-LIGHT + NORMAL * 0.3);
	float VdotBL = clamp(dot(VIEW, back_light), 0.0, 1.0);

	// Factor adicional: cuánto está la luz "detrás" de la superficie
	// Cuando la luz viene de atrás, -NdotL es positivo → más translucencia
	float back_factor = clamp(-dot(NORMAL, LIGHT), 0.0, 1.0);
	back_factor = pow(back_factor, 6.0); // o 3.0; concentra el efecto cuando realmente está backlit
	// Suaviza para que no sea un corte duro
	//back_factor = mix(0.3, 1.0, back_factor); // mínimo 0.3 incluso desde delante

	float sss = pow(VdotBL, translucency_power) * translucency_strength * back_factor;
	vec3 translucency = sss * ATTENUATION * LIGHT_COLOR * translucency_color.rgb;

    // === 3. Fresnel / Rim light ===
    float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
    vec3 rim = fresnel * rim_strength * ATTENUATION * LIGHT_COLOR / PI;

    // === 4. Ambient hemisférico ===
    // Mezcla cielo/suelo según orientación respecto al planeta
    float hemisphere_factor = dot(planet_normal, normalize(-light_direction)) * 0.5 + 0.5;
vec3 ambient = mix(ambient_color_bottom.rgb, ambient_color_top.rgb, hemisphere_factor);
    ambient *= ambient_intensity * ATTENUATION;

    // === 5. Sombra planetaria (día/noche) ===
    vec3 vertex_to_planet_dir = normalize(planet_position - vertex_position_global);
    float position_incidence = dot(vertex_to_planet_dir, normalize(-light_direction));
    float planet_shadow = smoothstep(-transition_width, transition_width, position_incidence);

    // === Composición final ===
    // Difuso + translucencia + rim afectados por sombra planetaria
    // Ambient siempre presente pero atenuado en lado nocturno
    vec3 lit = (diffuse + translucency + rim) * planet_shadow;
    vec3 amb = ambient * mix(0.3, 1.0, planet_shadow); // Noche no totalmente negra

    DIFFUSE_LIGHT += lit + amb;
}