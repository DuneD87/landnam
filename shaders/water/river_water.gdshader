shader_type spatial;
// Agua de ríos (RiverWater). UV.x avanza aguas abajo (1 = 10 m), UV.y cruza el cauce de 0 a 1;
// UV2.x es la pendiente del tramo (corriente y espuma de rápidos) y UV2.y la anchura relativa del río.
// Los lagos llevan UV2.x = -1 (agua quieta) y UV de mundo: un río en llano tiene pendiente 0 y no
// debe cambiar de textura.
//
// Lo que depende del búfer de profundidad (espesor, espuma de orilla, refracción) se apaga con la
// distancia: de lejos ese espesor es impreciso y salía agua oscura o salpicada de gris.
render_mode blend_mix, cull_disabled, depth_draw_opaque, specular_schlick_ggx;

uniform vec3 shallow_color : source_color = vec3(0.26, 0.52, 0.47);
uniform vec3 deep_color : source_color = vec3(0.08, 0.27, 0.32);
uniform vec3 far_color : source_color = vec3(0.17, 0.40, 0.42);
uniform vec3 sky_color : source_color = vec3(0.62, 0.76, 0.86);
uniform vec3 foam_color : source_color = vec3(0.90, 0.94, 0.95);
uniform float depth_fade = 2.5;
uniform float flow_speed = 0.35;
uniform float normal_strength = 0.4;
// Distancia (m) a la que se pasa del agua cercana (profundidad, refracción) al color lejano.
uniform float far_start = 60.0;
uniform float far_end = 300.0;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

varying float v_slope;

void vertex() {
	v_slope = UV2.x;
}

void fragment() {
	float view_dist = length(VERTEX);
	float far = smoothstep(far_start, far_end, view_dist);

	// Corriente: dos capas del mismo mapa a distinta escala y velocidad, en la dirección del cauce.
	float slope = max(v_slope, 0.0);
	// Velocidad única: si variase con la pendiente, TIME * velocidad estira la textura entre tramos
	// (cuanto más rato de partida, peor). La pendiente solo pone espuma y oleaje.
	float speed = flow_speed;
	vec2 base_uv = vec2(UV.x * 0.25, UV.y * 0.6);
	if (v_slope < -0.5) {
		base_uv = UV * 0.25;
		speed = 0.03;
	}
	vec3 n1 = texture(normal_map, base_uv + vec2(-TIME * speed, 0.0)).rgb;
	vec3 n2 = texture(normal_map, base_uv * 1.7 + vec2(-TIME * speed * 1.4, 0.37)).rgb;
	NORMAL_MAP = normalize(mix(n1, n2, 0.5));
	NORMAL_MAP_DEPTH = normal_strength * (1.0 + clamp(slope * 8.0, 0.0, 1.0)) * (1.0 - 0.7 * far);

	// Espesor de agua hasta el fondo (solo de cerca).
	float scene_depth = texture(depth_tex, SCREEN_UV).r;
	vec4 world = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	world.xyz /= world.w;
	float thickness = max(-world.z + VERTEX.z, 0.0);
	float t = clamp(thickness / depth_fade, 0.0, 1.0);

	vec3 near_col = mix(shallow_color, deep_color, t);
	vec2 refr = SCREEN_UV + (NORMAL_MAP.xy - 0.5) * 0.015 * t;
	vec3 under = texture(screen_tex, refr).rgb;
	near_col = mix(under * shallow_color * 1.8, near_col, smoothstep(0.0, 0.7, t));
	vec3 color = mix(near_col, far_color, far);

	// Cielo reflejado en ángulos rasantes.
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	color = mix(color, sky_color, fres * 0.55);

	// Espuma: línea fina en la orilla (de cerca) y manchas en los rápidos de verdad.
	float noise = texture(normal_map, base_uv * 3.0 + vec2(-TIME * speed * 2.0, 0.0)).r;
	float edge_foam = (1.0 - smoothstep(0.0, 0.25, thickness)) * (1.0 - far) * 0.6;
	float rapid_foam = smoothstep(0.04, 0.14, slope) * smoothstep(0.5, 0.8, noise) * 0.8 * (1.0 - 0.6 * far);
	float foam = clamp(edge_foam + rapid_foam, 0.0, 1.0);
	color = mix(color, foam_color, foam);

	ALBEDO = color;
	ROUGHNESS = mix(0.06, 0.5, foam);
	SPECULAR = 0.5;
	ALPHA = mix(mix(clamp(0.6 + t * 0.4, 0.0, 1.0), 0.95, far), 1.0, foam);
}
