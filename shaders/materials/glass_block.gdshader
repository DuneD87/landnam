shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

// Bloques de construcción traslúcidos (cristal). Aparte del tinte resuelve el caso que el quad de
// niebla no puede cubrir: con la cámara dentro de un compartimento seco, underwater.gdshader se
// descarta entero, así que una ventana sumergida se nieblea ella misma componiendo lo que hay
// detrás con la misma absorción e in-scatter que el quad (underwater_apply del include común).

#include "res://shaders/liquid/underwater_fog.gdshaderinc"

uniform vec4 glass_color : source_color = vec4(0.74, 0.85, 0.87, 0.14);
uniform float glass_roughness : hint_range(0.0, 1.0) = 0.25;
uniform float glass_specular : hint_range(0.0, 1.0) = 0.5;

// Agua y niebla: los empuja Underwater._process desde el material del quad, o sea el MISMO origen
// del que salen los suyos (dos cuentas independientes acaban divergiendo). Con water_radius = 0
// —planeta sin agua, o antes del primer frame de sincronización— el cristal es solo cristal.
uniform vec3 planet_center = vec3(0.0);
uniform float water_radius = 0.0;
uniform vec3 absorption_coefficients = vec3(0.45, 0.18, 0.06);
uniform float fog_density : hint_range(0.0, 4.0) = 1.0;
uniform float distance_depth_gain = 0.7;
uniform float distance_depth_max = 120.0;
uniform float scatter_vertical_range = 40.0;
uniform float tir_reflection_depth = 0.0; // profundidad extra a mano para el espejo TIR
uniform float atmosphere_leak_distance = 250.0;
uniform float atmosphere_leak_falloff = 0.08;
uniform vec3 sun_direction = vec3(0.0);
uniform float sun_glow_intensity = 0.35;
uniform float sun_glow_power = 8.0;

// 0 = off | 1 = clasificación (rojo aire, verde sumergido) | 2 = columna de agua
uniform int debug_mode : hint_range(0, 2) = 0;
uniform float debug_scale = 20.0;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Cristal normal. COLOR es el tinte de daño que mete ChunkMeshBuilder por color de vértice.
	vec4 base = glass_color * COLOR;
	ALBEDO = base.rgb;
	ALPHA = base.a;
	ROUGHNESS = glass_roughness;
	SPECULAR = glass_specular;
	METALLIC = 0.0;

	// Profundidad del panel bajo la superficie EN REPOSO. La ola no entra en la cuenta a
	// propósito: costaría el include entero de Gerstner por píxel y solo cambia el resultado en la
	// franja de ±amplitud, donde no hay ventanas que valga la pena nieblar.
	float pane_depth = water_radius - length(v_world_pos - planet_center);
	bool submerged = water_radius > 0.0 && pane_depth > 0.0;
	float column = 0.0;

	// Profundidad de la escena que hay detrás del panel. El depth buffer solo tiene opacos, así que
	// el propio cristal no está en él: en aire se devuelve tal cual y el buffer se queda igual.
	float depth_raw = textureLod(depth_texture, SCREEN_UV, 0.0).x;
	float out_depth = depth_raw;

	if (submerged) {
		vec3 ro = CAMERA_POSITION_WORLD;
		vec3 rd = normalize(v_world_pos - ro);
		float t_pane = length(v_world_pos - ro);

		vec4 view_coords = INV_PROJECTION_MATRIX * vec4(vec3(SCREEN_UV * 2.0 - 1.0, depth_raw), 1.0);
		view_coords.xyz /= view_coords.w;
		float scene_distance = length(view_coords.xyz);

		// El agua empieza en el panel y acaba donde el rayo sale de la esfera de agua o topa con
		// la escena, lo que ocurra antes: mirando al cielo por la ventana la columna es la que va
		// hasta la superficie, no hasta el infinito.
		float t_exit = ray_sphere_exit(planet_center, water_radius, ro, rd);
		if (t_exit < 0.0) {
			t_exit = scene_distance;
		}
		column = max(min(t_exit, scene_distance) - t_pane, 0.0) * fog_density;

		vec3 up = normalize(v_world_pos - planet_center);
		float scatter_depth = underwater_scatter_depth(pane_depth, dot(rd, up) * 0.5 + 0.5, column,
				scatter_vertical_range, distance_depth_gain, distance_depth_max);
		vec3 scatter = depth_tier_color(scatter_depth);

		// Halo hacia el sol, mismo convenio que el quad: sun_direction apunta HACIA el sol.
		vec3 to_sun = dot(sun_direction, sun_direction) > 1e-6 ? normalize(sun_direction) : up;
		float sun_glow = pow(max(dot(rd, to_sun), 0.0), sun_glow_power);
		scatter *= 1.0 + sun_glow * sun_glow_intensity;

		vec3 screen = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;

		// Reflexión interna total: si el rayo cruza la superficie antes que la escena y lo hace
		// por debajo del ángulo crítico, ahí no hay cielo sino agua profunda reflejada. Sin esto
		// una ventana sumergida enseña el cielo, sin distorsión y sin nieblar, en cuanto el rayo
		// apunta algo hacia arriba: la columna hasta la superficie es corta y no absorbe nada.
		if (t_exit < scene_distance) {
			vec3 exit_normal = normalize(ro + rd * t_exit - planet_center);
			float tir = underwater_tir_amount(rd, exit_normal);

			// El espejo no devuelve el agua que hay en el panel —eso sale casi con color de
			// superficie y lee como un reflejo del cielo—, sino lo que ve el rayo REFLEJADO: apunta
			// hacia abajo y se pierde en el fondo, así que se evalúa con su propia orientación y
			// con columna saturada, que es a donde converge cualquier rayo descendente.
			vec3 mirror_rd = reflect(rd, exit_normal);
			float mirror_depth = underwater_scatter_depth(pane_depth,
					dot(mirror_rd, up) * 0.5 + 0.5, 1.0e6,
					scatter_vertical_range, distance_depth_gain, distance_depth_max);
			screen = mix(screen, depth_tier_color(mirror_depth + tir_reflection_depth), tir);
		}

		vec3 fogged = underwater_apply(screen, absorption_coefficients, column, scatter);

		// El panel compone él mismo lo que se ve a través, así que sale por EMISSION (para que la
		// luz de la escena no lo multiplique) y deja de mezclarse por alpha: la niebla ya lleva el
		// fondo dentro y mezclarla otra vez lo contaría dos veces. El tinte tiñe lo transmitido, y
		// el especular se sigue sumando encima aunque el albedo sea negro.
		ALBEDO = vec3(0.0);
		EMISSION = fogged * mix(vec3(1.0), base.rgb, base.a);
		ALPHA = 1.0;

		// Fuga de atmósfera, igual que el quad: el compositor es POST_TRANSPARENT y se pinta
		// encima según el depth buffer, donde un píxel sin escena vale cielo entero. Se escribe la
		// profundidad de un punto del rayo cuya distancia decae con la columna de agua: velo pleno
		// con poca agua por delante, nada hacia el fondo.
		float leak_t = atmosphere_leak_distance * exp(-atmosphere_leak_falloff * column);
		leak_t = clamp(leak_t, 0.01, scene_distance * 0.995);
		vec4 leak_clip = PROJECTION_MATRIX * vec4(normalize(view_coords.xyz) * leak_t, 1.0);
		out_depth = clamp(leak_clip.z / leak_clip.w, 0.0, 1.0);
	}

	if (debug_mode == 1) {
		ALBEDO = vec3(0.0);
		EMISSION = submerged ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
		ALPHA = 1.0;
	} else if (debug_mode == 2) {
		ALBEDO = vec3(0.0);
		EMISSION = vec3(clamp(column / max(debug_scale, 0.001), 0.0, 1.0));
		ALPHA = 1.0;
	}

	DEPTH = out_depth;
}
