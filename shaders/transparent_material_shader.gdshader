shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

uniform vec4 albedo : source_color;
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0, 0.001);
uniform float point_size : hint_range(0.1, 128.0, 0.1);

uniform vec3 uv1_scale;
uniform vec3 uv1_offset;
uniform vec3 uv2_scale;
uniform vec3 uv2_offset;

uniform vec3 light_direction; // Dirección de la luz direccional
uniform vec3 planet_position; // Posición del centro del planeta
uniform float transition_width : hint_range(0.0, 1.0, 0.01) = 0.2; // Ancho de la transición suave

uniform vec3 wind_direction = vec3(1.0, 0.0, 0.0); // Dirección del viento
uniform float wind_speed : hint_range(0.0, 10.0, 0.01) = 1.0; // Velocidad/intensidad del viento

varying vec3 vertex_position_global; // Posición del vértice en el espacio global

// Función de ruido simple para aleatoriedad
float random(vec3 seed) {
    return fract(sin(dot(seed, vec3(12.9898, 78.233, 45.5432))) * 43758.5453);
}

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
	
	// Calcular la posición del vértice en el espacio global
	vertex_position_global = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// Efecto de viento: desplazar vértices según la dirección del viento
	float wind_strength = wind_speed * (0.5 + 0.5 * random(VERTEX)); // Aleatoriedad basada en posición
	vec3 wind_offset = wind_direction * sin(TIME * wind_speed + dot(VERTEX, vec3(0.5))) * wind_strength;
	VERTEX += wind_offset;
}

void fragment() {
	vec2 base_uv = UV;

	// Calcular el color base
	vec4 albedo_tex = texture(texture_albedo, base_uv);
	ALBEDO = albedo.rgb * albedo_tex.rgb;

	// Manejar transparencia
	ALPHA *= albedo.a * albedo_tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;

	// Calcular la incidencia de la luz usando la normal del vértice
	float light_incidence = dot(normalize(NORMAL), normalize(-light_direction));
	
	// Calcular la dirección desde el vértice al centro del planeta
	vec3 vertex_to_planet_dir = normalize(planet_position - vertex_position_global);
	
	// Determinar si el vértice está en el lado iluminado usando la posición
	float position_incidence = dot(vertex_to_planet_dir, normalize(-light_direction));
	
	// Combinar la iluminación (basada en NORMAL) con el oscurecimiento (basado en posición)
	float intensity = light_incidence * smoothstep(-transition_width, transition_width, position_incidence);
	ALBEDO = ALBEDO * clamp(intensity, 0.0, 1.0); // Interpolar hacia negro en las áreas no iluminadas
}