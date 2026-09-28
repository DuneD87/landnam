shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Hielo de la banquisa con volumen: témpanos (SeaIceFloes) e icebergs.
//
// Los témpanos flotan: cada uno se mueve entero con la ola en su centro (la misma superficie
// Gerstner que el agua, sin las octavas más cortas que él), cabecea con la normal del agua y deriva
// despacio donde la banquisa está abierta. SeaIceFloes._pose() es la réplica CPU de ese movimiento,
// para las colisiones: cambiar uno obliga a cambiar el otro.
//
// Los uniforms del oleaje (gerstner_waves.gdshaderinc) los copia SeaIceFloes del material del agua.
#include "res://shaders/liquid/gerstner_waves.gdshaderinc"

uniform float water_time = 0.0;
uniform vec3 planet_center = vec3(0.0);
// false = iceberg: no se mueve (demasiada masa para la ola que deja el hielo).
uniform bool floating = true;
// Los témpanos encogen hasta desaparecer entre estas distancias; más allá la banquisa la dibuja el
// agua (water_shader, ice_geometry_start/end).
uniform float fade_start = 380.0;
uniform float fade_end = 480.0;

uniform vec3 snow_color : source_color = vec3(0.90, 0.93, 0.97);
uniform vec3 bare_color : source_color = vec3(0.60, 0.73, 0.84);
uniform vec3 wall_color : source_color = vec3(0.60, 0.78, 0.88);
uniform vec3 deep_color : source_color = vec3(0.22, 0.62, 0.70);

// Posición en reposo relativa al planeta: la textura va pegada al hielo aunque se mueva.
varying vec3 v_rest;
// Vertical del planeta en reposo, altura sobre el mar en reposo y la cara hacia el cielo (en
// reposo: la nieve no resbala porque el témpano cabecee).
varying vec3 v_up;
varying float v_height;
varying float v_facing;
varying float v_seed;

float ice_hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}
const mat3 ICE_ROTATION = mat3(vec3(0.8, 0.6, 0.0), vec3(-0.48, 0.64, 0.6), vec3(0.36, -0.48, 0.8));
float ice_value_noise(vec3 p) {
	p = ICE_ROTATION * p;
	vec3 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(ice_hash(i), ice_hash(i + vec3(1, 0, 0)), f.x), mix(ice_hash(i + vec3(0, 1, 0)), ice_hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(ice_hash(i + vec3(0, 0, 1)), ice_hash(i + vec3(1, 0, 1)), f.x), mix(ice_hash(i + vec3(0, 1, 1)), ice_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// Giro de v alrededor del eje unitario `axis`.
vec3 rotate_about(vec3 v, vec3 axis, float angle) {
	float c = cos(angle), s = sin(angle);
	return v * c + cross(axis, v) * s + axis * dot(axis, v) * (1.0 - c);
}

// Giro mínimo que lleva `from` a `to` (unitarios).
vec3 rotate_between(vec3 v, vec3 from, vec3 to) {
	vec3 k = cross(from, to);
	float s2 = dot(k, k);
	if (s2 < 1e-10) {
		return v;
	}
	float c = dot(from, to);
	return v * c + cross(k, v) + k * (dot(k, v) * (1.0 - c) / s2);
}

void vertex() {
	mat3 model_basis = mat3(MODEL_MATRIX);
	vec3 world_rest = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 rest_normal = normalize(model_basis * NORMAL);
	v_rest = world_rest - planet_center;
	v_seed = 0.0;
	if (floating) {
		vec3 center_world = (MODEL_MATRIX * vec4(CUSTOM0.xyz, 1.0)).xyz;
		vec3 c = center_world - planet_center;
		vec3 up = normalize(c);
		WaveContext ctx = wave_context(c);
		vec3 n;
		float crest;
		// Olas más cortas que el témpano no lo mueven (SeaIceFloes.FLOE_WAVE_FILTER).
		vec3 disp = gerstner_surface_ctx(c, up, water_time, CUSTOM0.w * 1.2, ctx, n, crest);
		float open = 1.0 - smoothstep(0.85, 1.0, ctx.ice);
		float ph = CUSTOM1.x * 6.2831853;
		vec3 u = normalize(cross(up, abs(up.x) < 0.9 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0)));
		vec3 w = cross(u, up);
		vec3 drift = (u * sin(water_time * 0.071 + ph) + w * sin(water_time * 0.053 + ph * 1.7)) * (0.5 * open);
		float yaw = sin(water_time * 0.037 + ph * 2.3) * 0.06 * open;
		float fade = 1.0 - smoothstep(fade_start, fade_end, distance(center_world, CAMERA_POSITION_WORLD));

		vec3 offset = world_rest - center_world;
		v_height = dot(offset, up);
		v_facing = dot(rest_normal, up);
		v_up = up;
		v_seed = CUSTOM1.x;
		offset = rotate_between(rotate_about(offset, up, yaw), up, n);
		vec3 moved_normal = rotate_between(rotate_about(rest_normal, up, yaw), up, n);
		vec3 world = center_world + disp + drift + offset * fade;
		VERTEX = transpose(model_basis) * (world - MODEL_MATRIX[3].xyz);
		NORMAL = transpose(model_basis) * moved_normal;
	} else {
		v_up = normalize(v_rest);
		v_height = length(v_rest) - water_radius;
		v_facing = dot(rest_normal, v_up);
	}
}

void fragment() {
	vec3 p = v_rest;
	// Metros por píxel: las octavas finas se apagan antes de hacer moiré.
	float footprint = length(fwidth(p));
	float fine = 1.0 - smoothstep(0.15, 0.4, footprint);

	// Nieve venteada sobre lo que mira al cielo: manchas de hielo desnudo pequeñas y de borde nítido, no charcos difusos.
	float drift = ice_value_noise(p * 0.07) * 0.55 + mix(0.5, ice_value_noise(p * 0.31 + vec3(5.0)), fine) * 0.45;
	float snowy = smoothstep(0.26, 0.33, drift + v_seed * 0.1);
	float top = smoothstep(0.5, 0.8, v_facing);
	// Paredes: capas de hielo (estratos horizontales) y acanaladuras verticales del deshielo.
	float vertical = dot(p, v_up);
	vec3 flute_p = (p - v_up * vertical) * 0.35 + v_up * (vertical * 0.03);
	float flutes = ice_value_noise(flute_p);
	float strata = ice_value_noise(vec3(p.x * 0.05, v_height * 2.2, p.z * 0.05)) * 0.5
		+ flutes * 0.3 + ice_value_noise(p * 0.6) * 0.2 * fine;
	vec3 wall = wall_color * mix(0.8, 1.12, strata);
	// El pie de la pared, bañado por el agua, es hielo liso y más azul; bajo el agua, turquesa.
	float wet = 1.0 - smoothstep(-0.05, 0.35, v_height);
	wall = mix(wall, bare_color * 0.85, wet * 0.6);
	float under = 1.0 - smoothstep(-0.6, -0.1, v_height);
	wall = mix(wall, deep_color, under);
	// Cornisa de nieve en el canto de arriba de las paredes altas (icebergs).
	float cornice = smoothstep(0.1, 0.35, v_facing) * smoothstep(0.4, 2.0, v_height) * snowy;

	vec3 top_color = mix(bare_color, snow_color, snowy);
	top_color *= mix(1.0, mix(0.92, 1.04, ice_value_noise(p * 1.3)), fine);
	float snow_amount = top * mix(0.35, 1.0, snowy) + cornice * 0.6;
	ALBEDO = mix(wall, top_color, top);
	ALBEDO = mix(ALBEDO, snow_color, cornice * 0.6);
	ROUGHNESS = mix(0.5, mix(0.3, 0.85, snowy), top);
	ROUGHNESS = mix(ROUGHNESS, 0.15, wet * (1.0 - top));
	SPECULAR = 0.5;

	// Relieve: el gradiente de un solo ruido, fuerte en la nieve y suave en las paredes.
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 q = p * vec3(0.9, 0.9, 0.35);
	float h0 = ice_value_noise(q);
	vec3 slope = vec3(ice_value_noise(q + vec3(0.06, 0.0, 0.0)),
		ice_value_noise(q + vec3(0.0, 0.06, 0.0)),
		ice_value_noise(q + vec3(0.0, 0.0, 0.06))) - h0;
	slope -= world_normal * dot(slope, world_normal);
	// Sastrugi: surcos suaves de la nieve venteada, alargados en una dirección.
	world_normal = normalize(world_normal - slope * mix(0.8, 1.6, snow_amount) * fine);
	// Acanaladuras en las paredes: el gradiente horizontal del mismo ruido estirado en vertical.
	float wall_amount = (1.0 - top) * (1.0 - under);
	if (wall_amount > 0.01) {
		vec3 fs = vec3(ice_value_noise(flute_p + vec3(0.05, 0.0, 0.0)), ice_value_noise(flute_p + vec3(0.0, 0.05, 0.0)),
			ice_value_noise(flute_p + vec3(0.0, 0.0, 0.05))) - flutes;
		fs -= world_normal * dot(fs, world_normal);
		fs -= v_up * dot(fs, v_up);
		world_normal = normalize(world_normal - fs * 7.0 * wall_amount);
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);

	// Luz que atraviesa los cantos finos del hielo.
	BACKLIGHT = wall_color * 0.35 * (1.0 - top);
}
