#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict image2D color_image;
layout(set = 0, binding = 1) uniform sampler2D depth_texture;

layout(set = 0, binding = 2, std430) readonly restrict buffer ParamsBuffer {
	vec4 data[];
} params_buffer;

#define P(i) params_buffer.data[i]

const float EPSILON = 0.000001;
const float MAX_FLOAT = 3.402823466e+38;

// Si te quedas corto de rendimiento, baja a 6/6. Si ves bandas, sube a 16/12.
const int NUM_IN_SCATTER_POINTS    = 10;
const int NUM_OPTICAL_DEPTH_POINTS = 10;


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

	vec3 light = calculate_light(
		entry_point,
		ray_dir,
		dst_through_atmo - EPSILON * 2.0,
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

	imageStore(color_image, pixel, vec4(light, scene_color.a));
}