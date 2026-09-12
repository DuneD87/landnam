shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

// Pasada 2 del cristal: el reflejo, con ALPHA = fracción de Fresnel. La transmisión la pone antes
// glass_block_tint.gdshader multiplicando, así que entre las dos sale fondo*tinte*(1-R) + cielo*R.
// Un panel sumergido se nieblea además él mismo: el compositor excluye el agua con la cámara
// dentro de un compartimento seco, y una ventana es lo único que puede mirar fuera desde ahí.

#include "res://shaders/liquid/underwater_fog.gdshaderinc"
#include "res://shaders/liquid/ship_interiors.gdshaderinc"
uniform vec3 waterline_point;
uniform vec3 waterline_normal;
// calculate_sky_color(): el cielo hay que sintetizarlo, no existe cubemap que reflejar (el del
// Environment es el espacio exterior y el cielo visible lo pinta el compositor). Mismo que el agua.
#include "res://shaders/lib/sky_reflection.gdshaderinc"
#include "res://shaders/lib/glass_common.gdshaderinc"

uniform float glass_roughness : hint_range(0.0, 1.0) = 0.25;
uniform float glass_specular : hint_range(0.0, 1.0) = 0.5;
// Reflectancia frontal del vidrio: 0.04 es el valor físico de un dieléctrico de n = 1.5.
uniform float glass_f0 : hint_range(0.0, 1.0) = 0.04;
// Tope del reflejo: a rasante el panel se acerca a espejo, y el reflejo de dos paneles apilados se
// separa tanto del de uno que se acaba leyendo el contorno de cada bloque.
uniform float glass_reflect_max : hint_range(0.0, 1.0) = 0.55;
// Exponente de Schlick. El físico es 5; bajarlo reparte el reflejo por toda la cara.
uniform float glass_fresnel_power : hint_range(1.0, 8.0) = 5.0;
uniform float sky_influence : hint_range(0.0, 4.0) = 1.0;

// Agua y niebla: los empuja Underwater._process desde el material de parámetros, o sea el MISMO origen
// del que salen los suyos (dos cuentas independientes acaban divergiendo). planet_center y
// water_radius viven en glass_common, compartidos con la pasada de transmisión.
uniform vec3 absorption_coefficients = vec3(0.45, 0.18, 0.06);
uniform float fog_density : hint_range(0.0, 4.0) = 1.0;
uniform float distance_depth_gain = 0.7;
uniform float distance_depth_max = 120.0;
uniform float scatter_vertical_range = 40.0;
uniform float tir_reflection_depth = 0.0;
uniform float atmosphere_leak_distance = 250.0;
uniform float atmosphere_leak_falloff = 0.08;
uniform vec3 sun_direction = vec3(0.0);
uniform float sun_glow_intensity = 0.35;
uniform float sun_glow_power = 8.0;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 world_up = normalize(v_world_pos - planet_center);

	// Fresnel de Schlick: casi invisible de frente, espejo a rasante.
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float reflect_amount = glass_f0 + (1.0 - glass_f0) * pow(1.0 - ndv, glass_fresnel_power);
	reflect_amount = min(reflect_amount, glass_reflect_max);

	vec3 to_sun_w = dot(sun_direction, sun_direction) > 1e-6 ? normalize(sun_direction) : world_up;
	float day = smoothstep(-0.1, 0.15, dot(world_up, to_sun_w));
	vec3 view_w = normalize(v_world_pos - CAMERA_POSITION_WORLD);
	vec3 normal_w = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 sky = calculate_sky_color(reflect(view_w, normal_w), world_up, day) * sky_influence;

	// ALPHA es la fracción reflejada y nada más: lo transmitido ya lo tiñó la pasada anterior.
	// COLOR es el tinte de daño, por color de vértice.
	ALPHA = clamp(reflect_amount, 0.0, 1.0);
	ALBEDO = vec3(0.0);
	EMISSION = sky * COLOR.rgb;
	ROUGHNESS = glass_roughness;
	SPECULAR = glass_specular;
	METALLIC = 0.0;

	// La ola no entra en la cuenta a propósito: costaría el include entero de Gerstner por píxel y
	// solo cambia el resultado en la franja de ±amplitud, donde no hay ventanas que nieblar.
	float pane_depth = glass_pane_depth(v_world_pos);

	// El depth buffer solo tiene opacos, así que el propio cristal no está en él: en aire se
	// devuelve tal cual y el buffer se queda igual.
	float depth_raw = textureLod(depth_texture, SCREEN_UV, 0.0).x;
	float out_depth = depth_raw;

	// Wet pixels now receive optical transport after ALL transparents. Applying it
	// here too would double the absorption and write artificial depth in the ocean.
	vec4 near_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, 1.0, 1.0);
	vec3 near_offset = mat3(INV_VIEW_MATRIX) * (near_view.xyz / near_view.w);
	bool compositor_water = waterline_signed_relative(CAMERA_POSITION_WORLD, near_offset, waterline_point, waterline_normal) < 0.0
		&& !inside_ship_interior(CAMERA_POSITION_WORLD);
	if (pane_depth > 0.0 && !compositor_water) {
		vec3 ro = CAMERA_POSITION_WORLD;
		vec3 rd = normalize(v_world_pos - ro);
		float t_pane = length(v_world_pos - ro);

		vec4 view_coords = INV_PROJECTION_MATRIX * vec4(vec3(SCREEN_UV * 2.0 - 1.0, depth_raw), 1.0);
		view_coords.xyz /= view_coords.w;
		float scene_distance = length(view_coords.xyz);

		// La columna acaba donde el rayo sale del agua o topa con la escena, lo que ocurra antes.
		float t_exit = ray_sphere_exit(planet_center, water_radius, ro, rd);
		if (t_exit < 0.0) {
			t_exit = scene_distance;
		}
		float column = max(min(t_exit, scene_distance) - t_pane, 0.0) * fog_density;

		float scatter_depth = underwater_scatter_depth(pane_depth, dot(rd, world_up) * 0.5 + 0.5,
				column, scatter_vertical_range, distance_depth_gain, distance_depth_max);
		vec3 scatter = depth_tier_color(scatter_depth);

		// Halo hacia el sol, mismo convenio que el compositor: sun_direction apunta HACIA el sol.
		float sun_glow = pow(max(dot(rd, to_sun_w), 0.0), sun_glow_power);
		scatter *= 1.0 + sun_glow * sun_glow_intensity;

		vec3 screen = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;

		// Reflexión interna total: pasado el ángulo crítico la superficie no es ventana al cielo
		// sino espejo del agua profunda. Sin esto la ventana enseña cielo crudo mirando hacia
		// arriba, donde la columna hasta la superficie es corta y no absorbe.
		if (t_exit < scene_distance) {
			vec3 exit_normal = normalize(ro + rd * t_exit - planet_center);
			float tir = underwater_tir_amount(rd, exit_normal);

			// El espejo devuelve lo que ve el rayo REFLEJADO, que apunta al fondo: su orientación
			// y columna saturada. Con las del rayo directo salía casi color de superficie.
			vec3 mirror_rd = reflect(rd, exit_normal);
			float mirror_depth = underwater_scatter_depth(pane_depth,
					dot(mirror_rd, world_up) * 0.5 + 0.5, 1.0e6,
					scatter_vertical_range, distance_depth_gain, distance_depth_max);
			screen = mix(screen, depth_tier_color(mirror_depth + tir_reflection_depth), tir);
		}

		// Ya lleva el fondo dentro: por EMISSION para que la luz de la escena no lo multiplique, y
		// con ALPHA = 1 para no mezclarlo otra vez contra el mismo fondo.
		ALBEDO = vec3(0.0);
		EMISSION = underwater_apply(screen, absorption_coefficients, column, scatter) * COLOR.rgb;
		ALPHA = 1.0;

		// Tratamiento heredado de ventanas vistas desde un compartimento seco: el compositor pinta cielo
		// donde el depth buffer no tiene escena. La distancia escrita decae con la columna de agua.
		float leak_t = atmosphere_leak_distance * exp(-atmosphere_leak_falloff * column);
		leak_t = clamp(leak_t, 0.01, scene_distance * 0.995);
		vec4 leak_clip = PROJECTION_MATRIX * vec4(normalize(view_coords.xyz) * leak_t, 1.0);
		out_depth = clamp(leak_clip.z / leak_clip.w, 0.0, 1.0);
	}

	// Falsear la profundidad solo vale si el panel está DELANTE de la escena opaca; detrás hay que
	// escribir la suya o el z-test lo deja pasar y el cristal se ve a través de las paredes.
	DEPTH = (FRAGCOORD.z >= depth_raw) ? out_depth : FRAGCOORD.z;
}
