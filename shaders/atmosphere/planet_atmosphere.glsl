#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict image2D color_image;
layout(set = 0, binding = 1) uniform sampler2D depth_texture;

layout(set = 0, binding = 2, std430) readonly restrict buffer ParamsBuffer {
	vec4 data[];
} params_buffer;

#define P(i) params_buffer.data[i]

const float EPSILON   = 0.000001;
const float MAX_FLOAT = 3.402823466e+38;
const float PI        = 3.14159265359;

// Atmósfera — baja a 6/6 para rendimiento, sube a 16/12 para menos bandas.
const int NUM_IN_SCATTER_POINTS    = 10;
const int NUM_OPTICAL_DEPTH_POINTS = 10;

// Nubes — baja a 8/3 para rendimiento, sube a 32/6 para más detalle.
const int NUM_CLOUD_STEPS       = 32;
const int NUM_CLOUD_LIGHT_STEPS = 4;

float cloud_underside_darkening(
	vec3 p,
	vec3 planet_center,
	float cloud_min_r,
	float cloud_max_r
) {
	float thickness = max(cloud_max_r - cloud_min_r, 0.001);
	float h = clamp((length(p - planet_center) - cloud_min_r) / thickness, 0.0, 1.0);

	// 1 abajo, 0 arriba.
	float lower_part = 1.0 - smoothstep(0.15, 0.75, h);

	// Valor de prueba visible.
	// 0.55 = bastante visible. Luego puedes subirlo a 0.70 / 0.80.
	return mix(1.0, 0.25, lower_part);
}

mat4 get_inv_projection() {
	return mat4(P(1), P(2), P(3), P(4));
}

vec3 view_to_world_dir(vec3 view_dir) {
	vec3 bx = P(5).xyz;
	vec3 by = P(6).xyz;
	vec3 bz = P(7).xyz;
	return bx * view_dir.x + by * view_dir.y + bz * view_dir.z;
}

vec3 reconstruct_view_position(vec2 uv, float depth) {
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
	vec4 view = get_inv_projection() * vec4(ndc, 1.0);
	if (abs(view.w) > EPSILON) {
		view.xyz /= view.w;
	}
	return view.xyz;
}

// Devuelve (dst_to_sphere, dst_through_sphere). Si no impacta: (MAX, 0).
vec2 ray_sphere(vec3 center, float radius, vec3 ro, vec3 rd) {
	vec3 oc = ro - center;
	float b = dot(oc, rd);
	float c = dot(oc, oc) - radius * radius;
	float h = b * b - c;
	if (h < 0.0) return vec2(MAX_FLOAT, 0.0);
	h = sqrt(h);
	float t0 = -b - h;
	float t1 = -b + h;
	if (t1 < 0.0) return vec2(MAX_FLOAT, 0.0);
	float dst_to = max(t0, 0.0);
	return vec2(dst_to, t1 - dst_to);
}


// ===== NUBES VOLUMÉTRICAS =====

float _hash3f(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float _vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(_hash3f(i),               _hash3f(i + vec3(1,0,0)), u.x),
		    mix(_hash3f(i + vec3(0,1,0)), _hash3f(i + vec3(1,1,0)), u.x), u.y),
		mix(mix(_hash3f(i + vec3(0,0,1)), _hash3f(i + vec3(1,0,1)), u.x),
		    mix(_hash3f(i + vec3(0,1,1)), _hash3f(i + vec3(1,1,1)), u.x), u.y),
		u.z);
}

float _fbm(vec3 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 4; i++, a *= 0.5) {
		v += a * _vnoise(p);
		p = p * 2.1 + vec3(1.7, 9.2, 3.4);
	}
	return v;
}

float cloud_sun_visibility(
	vec3 p,
	vec3 sun_dir,
	vec3 planet_center,
	float planet_radius,
	float softness
) {
	vec3 oc = p - planet_center;

	// Si proj < 0, el punto está en el lado opuesto al sol.
	float proj = dot(oc, sun_dir);

	// Distancia del punto al eje de la sombra cilíndrica del planeta.
	vec3 closest = oc - sun_dir * proj;
	float axis_dist = length(closest);

	// Dentro del cilindro de sombra: oscuro.
	float visibility = smoothstep(
		planet_radius - softness,
		planet_radius + softness,
		axis_dist
	);

	// En el lado diurno no debe bloquearse.
	if (proj > 0.0) {
		visibility = 1.0;
	}

	return visibility;
}

float sample_cloud_density(
	vec3 p, vec3 planet_center,
	float cloud_min_r, float cloud_max_r,
	float coverage, float density_scale, float noise_scale
) {
	vec3 local = p - planet_center;
	float dist = length(local);

	if (dist < cloud_min_r || dist > cloud_max_r) {
		return 0.0;
	}

	vec3 dir = local / max(dist, EPSILON);

	float thickness = max(cloud_max_r - cloud_min_r, 0.001);
	float h = clamp((dist - cloud_min_r) / thickness, 0.0, 1.0);

	float height_grad =
		smoothstep(0.0, 0.2, h) *
		smoothstep(1.0, 0.5, h);

	// noise_scale ahora actúa como frecuencia alrededor del planeta.
	// Valores típicos: 8 - 40.
	float reference_r = max((cloud_min_r + cloud_max_r) * 0.5, 1.0);
	float freq = max(noise_scale, 0.001);

	// Ruido anclado al planeta, no a la cámara.
	vec3 noise_pos = (local / reference_r) * freq;

	// Variación vertical radial. Valor pequeño (0.5–1.0) evita deformación al mover la cámara.
	noise_pos += dir * (h * 0.8);

	float base = _fbm(noise_pos) * 1.0667;

	float density = max(0.0, base - (1.0 - coverage));
	return density * height_grad * density_scale;
}

float hg_phase(float cos_theta, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (4.0 * PI * pow(max(1.0 + g2 - 2.0 * g * cos_theta, 0.001), 1.5));
}

float cloud_light_od(
	vec3 p, vec3 sun_dir,
	vec3 planet_center, float cloud_min_r, float cloud_max_r,
	float coverage, float density_scale, float noise_scale
) {
	vec2 hit = ray_sphere(planet_center, cloud_max_r, p, sun_dir);
	if (hit.y <= 0.0) return 0.0;
	float step_sz = hit.y / float(NUM_CLOUD_LIGHT_STEPS);
	float od = 0.0;
	vec3 lp = p + sun_dir * (step_sz * 0.5);
	for (int i = 0; i < NUM_CLOUD_LIGHT_STEPS; i++) {
		od += sample_cloud_density(lp, planet_center, cloud_min_r, cloud_max_r,
		                           coverage, density_scale, noise_scale) * step_sz;
		lp += sun_dir * step_sz;
	}
	return od;
}

void march_clouds(
	vec3 ro, vec3 rd, float max_dist,
	vec3 planet_center, float cloud_min_r, float cloud_max_r,
	float density_scale, float coverage,
	float absorption, float g, float noise_scale,
	vec3 sun_dir, float sun_intensity, float planet_radius,
	float jitter,
	out vec3 out_color, out float out_trans
) {
	out_color = vec3(0.0);
	out_trans = 1.0;

	vec2 outer = ray_sphere(planet_center, cloud_max_r, ro, rd);
	if (outer.y <= 0.0) return;

	float t0 = outer.x;
	float t1 = outer.x + outer.y;

	// Recortar por la esfera interior (base de la capa de nubes).
	// - Cámara DENTRO de la esfera interior (en superficie): inner.x == 0, marchar desde la salida.
	// - Cámara FUERA de la esfera interior: cortar t1 antes de entrar en ella.
	vec2 inner = ray_sphere(planet_center, cloud_min_r, ro, rd);

	if (inner.y > 0.0) {
		float ro_r = length(ro - planet_center);

		// Cámara debajo de la base de las nubes: empezar al salir de la esfera interior.
		if (ro_r < cloud_min_r) {
			t0 = max(t0, inner.x + inner.y);
		}
		// Cámara fuera de la esfera interior: cortar antes de entrar en ella.
		else {
			t1 = min(t1, inner.x);
		}
	}

	t0 = max(t0, 0.0);
	t1 = min(t1, max_dist);
	if (t1 <= t0 + 0.001) return;

	float step_size = (t1 - t0) / float(NUM_CLOUD_STEPS);
	vec3 p = ro + rd * (t0 + step_size * jitter);
	float cos_theta = dot(rd, sun_dir);
	float phase = hg_phase(cos_theta, g);

	for (int i = 0; i < NUM_CLOUD_STEPS; i++) {
		float d = sample_cloud_density(p, planet_center, cloud_min_r, cloud_max_r,
		                               coverage, density_scale, noise_scale);
		if (d > 0.0001) {
			float l_od = cloud_light_od(p, sun_dir, planet_center, cloud_min_r, cloud_max_r,
										coverage, density_scale, noise_scale);

			float shadow_softness = max(cloud_max_r - cloud_min_r, planet_radius * 0.005);

			float shadow = cloud_sun_visibility(
				p,
				sun_dir,
				planet_center,
				planet_radius,
				shadow_softness
			);

			float beer   = exp(-l_od * absorption);
			float powder = 1.0 - exp(-d * step_size * absorption * 2.0);

			float direct_light = beer * powder * 2.0 * phase * shadow;
			float ambient_light = 0.10 * shadow;
			float night_light = 0.0;

			// Oscurecimiento de la parte inferior de la nube
			float underside = cloud_underside_darkening(
				p,
				planet_center,
				cloud_min_r,
				cloud_max_r
			);

			// Gradiente día/noche y tinte de atardecer: sincronizan las nubes con la atmósfera.
			vec3 to_cloud = normalize(p - planet_center);
			float sun_dot_c = dot(to_cloud, sun_dir);
			float day_night = smoothstep(-0.15, 0.15, sun_dot_c);
			float sunset_f  = 1.0 - smoothstep(0.0, 0.3, abs(sun_dot_c));
			vec3  sunset_tint = mix(vec3(1.0), vec3(3.0, 0.45, 0.05), sunset_f);

			vec3 lighting = vec3((direct_light + ambient_light) * sun_intensity + night_light)
			                * underside * sunset_tint * day_night;

			float s_trans = exp(-d * step_size * absorption);

			out_color += out_trans * (1.0 - s_trans) * lighting;
			out_trans *= s_trans;

			if (out_trans < 0.005) { out_trans = 0.0; break; }
		}
		p += rd * step_size;
	}
}


float density_at_point(
	vec3 p,
	vec3 planet_center,
	float planet_radius,
	float atmo_radius,
	float density_falloff
) {
	float h = length(p - planet_center) - planet_radius;
	float thickness = max(atmo_radius - planet_radius, 0.001);
	float h01 = clamp(h / thickness, 0.0, 1.0);
	return exp(-h01 * density_falloff) * (1.0 - h01);
}


float optical_depth(
	vec3 ro,
	vec3 rd,
	float ray_length,
	vec3 planet_center,
	float planet_radius,
	float atmo_radius,
	float density_falloff
) {
	vec3 p = ro;
	float step_size = ray_length / float(NUM_OPTICAL_DEPTH_POINTS - 1);
	float od = 0.0;
	for (int i = 0; i < NUM_OPTICAL_DEPTH_POINTS; i++) {
		od += density_at_point(p, planet_center, planet_radius, atmo_radius, density_falloff) * step_size;
		p += rd * step_size;
	}
	return od;
}


vec3 calculate_light(
	vec3 ro,
	vec3 rd,
	float ray_length,
	vec3 original_color,
	vec3 sun_dir,
	vec3 planet_center,
	float planet_radius,
	float atmo_radius,
	float density_falloff,
	vec3 scattering_coeffs,
	float sun_intensity,
	float view_from_space
) {
	vec3 in_scatter_point = ro;
	float step_size = ray_length / float(NUM_IN_SCATTER_POINTS - 1);
	vec3 in_scattered_light = vec3(0.0);
	float view_ray_optical_depth = 0.0;

	for (int i = 0; i < NUM_IN_SCATTER_POINTS; i++) {
		// Sombra suave angular: transición gradual alrededor del terminador.
		// sun_dot > 0 → día, sun_dot < 0 → noche; smoothstep da el gradiente.
		vec3 to_scatter = normalize(in_scatter_point - planet_center);
		float sun_dot = dot(to_scatter, sun_dir);
		float shadow_factor = smoothstep(-0.15, 0.15, sun_dot);

		// Distancia desde el punto de muestra hasta salir de la atmósfera siguiendo al sol.
		float sun_ray_length = ray_sphere(planet_center, atmo_radius, in_scatter_point, sun_dir).y;
		float sun_ray_od = optical_depth(
			in_scatter_point, sun_dir, sun_ray_length,
			planet_center, planet_radius, atmo_radius, density_falloff
		);

		// Optical depth desde el punto de muestra hacia el origen del rayo (cámara/entrada).
		view_ray_optical_depth = optical_depth(
			in_scatter_point, -rd, step_size * float(i),
			planet_center, planet_radius, atmo_radius, density_falloff
		);

		vec3 transmittance = exp(-(sun_ray_od + view_ray_optical_depth) * scattering_coeffs);
		float local_density = density_at_point(
			in_scatter_point, planet_center, planet_radius, atmo_radius, density_falloff
		);

		// Tinte cálido en el terminador: rojo-naranja cuando sun_dot ≈ 0.
		float sunset_factor = 1.0 - smoothstep(0.0, 0.3, abs(sun_dot));
		vec3 sunset_tint = mix(vec3(1.0), vec3(3.0, 0.45, 0.05), sunset_factor);

		in_scattered_light += local_density * transmittance * scattering_coeffs * step_size * shadow_factor * sunset_tint;
		in_scatter_point += rd * step_size;
	}

	in_scattered_light *= sun_intensity;

	// Oscurecer la superficie del planeta en el lado nocturno (solo desde el espacio).
	vec3 lit_original = original_color;
	if (view_from_space > 0.5) {
		vec2 planet_hit = ray_sphere(planet_center, planet_radius + 400, ro, rd);
		if (planet_hit.y > 0.0) {
			vec3 surface_pt = ro + rd * planet_hit.x;
			float sn_dot = dot(normalize(surface_pt - planet_center), sun_dir);
			lit_original *= mix(0.05, 1.0, smoothstep(-0.15, 0.15, sn_dot));
		}
	}

	// Atenuación de lo que había detrás (terreno, objetos, cielo).
	vec3 original_color_transmittance = exp(-view_ray_optical_depth * scattering_coeffs);
	return lit_original * original_color_transmittance + in_scattered_light;
}


void main() {
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(P(0).xy);
	if (pixel.x >= size.x || pixel.y >= size.y) return;

	vec4 scene_color = imageLoad(color_image, pixel);

	float enabled = P(11).w;
	if (enabled < 0.5) {
		imageStore(color_image, pixel, scene_color);
		return;
	}

	vec2 uv = (vec2(pixel) + vec2(0.5)) / vec2(size);

	float planet_radius       = P(0).z;
	float atmo_radius         = P(0).w;
	float density_falloff     = P(5).w;
	float scattering_strength = P(6).w;
	float sun_intensity       = P(7).w;

	vec3 camera_position = P(8).xyz;          // (0,0,0): trabajamos relativo a cámara.
	vec3 planet_center   = P(9).xyz;
	vec3 sun_direction   = normalize(P(10).xyz);
	vec3 wavelengths     = P(11).rgb;         // nm (p.ej. 700, 530, 440)

	// Coeficientes de scattering tipo Rayleigh: (400/λ)^4 * strength.
	vec3 scattering_coefficients = vec3(
		pow(400.0 / max(wavelengths.r, 1.0), 4.0),
		pow(400.0 / max(wavelengths.g, 1.0), 4.0),
		pow(400.0 / max(wavelengths.b, 1.0), 4.0)
	) * scattering_strength;

	// Dirección del rayo en mundo.
	vec3 view_probe = reconstruct_view_position(uv, 0.0001);
	vec3 ray_dir = normalize(view_to_world_dir(view_probe));

	// Profundidad de escena (Godot reverse-Z: cerca ~1, lejos/cielo ~0).
	float depth_sample = texelFetch(depth_texture, pixel, 0).r;
	bool has_scene_depth = depth_sample > 1e-7;
	float scene_t = MAX_FLOAT;
	if (has_scene_depth) {
		vec3 scene_view_position = reconstruct_view_position(uv, depth_sample);
		scene_t = length(scene_view_position);
	}

	// Intersección con la atmósfera.
	vec2 atmo = ray_sphere(planet_center, atmo_radius, camera_position, ray_dir);
	float dst_to_atmo      = atmo.x;
	float dst_through_atmo = atmo.y;

	// Limita el recorrido por el terreno/objetos (clave para que se vea atmósfera sobre el suelo).
	dst_through_atmo = min(dst_through_atmo, max(scene_t - dst_to_atmo, 0.0));

	if (dst_through_atmo <= 0.0) {
		imageStore(color_image, pixel, scene_color);
		return;
	}

	vec3 entry_point = camera_position + ray_dir * (dst_to_atmo + EPSILON);

	float view_from_space = dst_to_atmo > EPSILON ? 1.0 : 0.0;

	// Nubes volumétricas — se aplican antes del scattering atmosférico.
	// 1. Primero calcula la atmósfera sobre la escena original.
	vec3 light = calculate_light(
		entry_point,
		ray_dir,
		max(dst_through_atmo - EPSILON * 2.0, 0.0),
		scene_color.rgb,
		sun_direction,
		planet_center,
		planet_radius,
		atmo_radius,
		density_falloff,
		scattering_coefficients,
		sun_intensity,
		view_from_space
	);

	// 2. Después compón las nubes delante de la atmósfera.
	if (P(13).w > 0.5) {
		float cloud_min_r = planet_radius + P(12).x;
		float cloud_max_r = planet_radius + P(12).y;

		vec3  cloud_col;
		float cloud_trans;

		float cloud_max_dist = min(scene_t, dst_to_atmo + dst_through_atmo);

		// Jitter por píxel: desplaza el origen del march de forma distinta en cada píxel
		// para que los artefactos de escalón no sean coherentes al mover la cámara.
		float cloud_jitter = _hash3f(vec3(float(pixel.x), float(pixel.y), 0.0));

		march_clouds(
			camera_position, ray_dir, cloud_max_dist,
			planet_center, cloud_min_r, cloud_max_r,
			P(12).z, P(12).w,
			P(13).x, P(13).y, P(13).z,
			sun_direction, sun_intensity, planet_radius,
			cloud_jitter,
			cloud_col, cloud_trans
		);

		light = light * cloud_trans + cloud_col;
	}

	imageStore(color_image, pixel, vec4(light, scene_color.a));
}