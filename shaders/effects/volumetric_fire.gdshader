shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_always, skip_vertex_transform;

// Fuego volumétrico raymarched genérico (antorcha, hoguera, brasero...): forma, tamaño, color y
// coste dependen solo de uniforms; cada prop lleva su propio ShaderMaterial. Adaptado de
// Dari0us/Godot-Spatial-Fire-Raymarched a planetas esféricos: el volumen crece desde el origen del
// nodo a lo largo de 'up_axis' (contra la gravedad), que un script pone por instancia.

instance uniform vec3 up_axis = vec3(0.0, 1.0, 0.0);

group_uniforms quality;
uniform int raymarch_steps : hint_range(2, 32) = 14;

group_uniforms shape;
uniform float fire_height = 0.55;
uniform float fire_width = 0.24;
uniform float taper_factor : hint_range(0.0, 1.0) = 0.45;
uniform float sharpness_cutoff : hint_range(0.05, 20.0) = 1.5;
uniform float density : hint_range(1.0, 300.0) = 60.0;

group_uniforms noise_motion;
uniform sampler3D noise_tex : repeat_enable;
uniform float time_scale = 0.03;
uniform float noise_scale = 2.0;
uniform float noise_threshold : hint_range(0.0, 1.0) = 0.43;
uniform float wobble_strength = 0.25;
uniform float wobble_speed = 6.0;
uniform float wobble_noise_frequency : hint_range(0.05, 10.0) = 0.5;

group_uniforms colors;
uniform float emission_strength = 2.5;
uniform float core_glow_multiplier : hint_range(0.0, 20.0) = 8.0;
uniform vec3 color_core : source_color = vec3(1.0, 0.9, 0.5);
uniform vec3 color_mid : source_color = vec3(1.0, 0.625, 0.0);
uniform vec3 color_outer : source_color = vec3(0.8, 0.01, 0.0);
uniform vec3 color_smoke : source_color = vec3(0.0);

group_uniforms blending;
uniform sampler2D depth_texture : hint_depth_texture;
uniform float proximity_fade_distance = 0.12;

varying vec3 world_pos;

// Radio de la esfera que envuelve el volumen del fuego (con margen para wobble y distorsión).
float bound_radius() {
	return 0.5 * length(vec2(fire_width * 1.6, fire_height * 1.15));
}

float get_noise(vec3 p, float scale_factor, float time_offset) {
	return texture(noise_tex, p * scale_factor + vec3(0.0, time_offset, 0.0)).r;
}

float sdf_ellipsoid(vec3 p, vec3 r) {
	float k0 = length(p / r);
	float k1 = length(p / (r * r));
	return k0 * (k0 - 1.0) / k1;
}

// Desplazamiento caótico por muestra: tres canales de ruido desfasados en el espacio y el tiempo.
vec3 wobble_offset(vec3 p, float t_anim) {
	float wx = get_noise(p + vec3(100.0, 0.0, 0.0), wobble_noise_frequency, t_anim * wobble_speed);
	float wy = get_noise(p + vec3(0.0, 200.0, 0.0), wobble_noise_frequency, t_anim * wobble_speed * 1.2);
	float wz = get_noise(p + vec3(0.0, 0.0, 300.0), wobble_noise_frequency, t_anim * wobble_speed * 0.8);
	return (vec3(wx, wy, wz) - 0.5) * wobble_strength;
}

// SDF del fuego en coordenadas locales (y centrada en el volumen): elipsoide con taper hacia
// arriba (base y techo redondeados), distorsionado por ruido para romper la silueta.
float fire_sdf(vec3 local_p, vec3 wobble, float t_anim) {
	vec3 box_size = vec3(fire_width, fire_height, fire_width);
	float nh = (local_p.y + fire_height * 0.5) / fire_height;
	float taper = max(0.01, 1.0 - nh * taper_factor);
	vec3 tapered = local_p;
	tapered.xz /= taper;
	float dist = sdf_ellipsoid(tapered, box_size * 0.5);
	dist += get_noise(local_p + wobble, noise_scale * 0.5, t_anim * 20.0) * fire_width * 0.13;
	return dist;
}

// Billboard esférico centrado en el volumen: el quad es solo la ventana por la que se marcha.
// Ignora escala/rotación local del mesh (skip_vertex_transform).
void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 axis = normalize(up_axis);
	vec3 center = origin + axis * (fire_height * 0.5);
	float radius = bound_radius();
	vec3 cam_right = INV_VIEW_MATRIX[0].xyz;
	vec3 cam_up = INV_VIEW_MATRIX[1].xyz;
	world_pos = center
		+ cam_right * ((UV.x - 0.5) * 2.0 * radius)
		+ cam_up * ((0.5 - UV.y) * 2.0 * radius);
	VERTEX = (VIEW_MATRIX * vec4(world_pos, 1.0)).xyz;
}

// Raymarch front-to-back dentro de la esfera envolvente, con jitter por píxel contra el banding.
// Densidad = interior del SDF modelado por umbral de ruido; color outer→mid→core más humo arriba.
void fragment() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 axis = normalize(up_axis);
	vec3 tan1 = normalize(cross(axis, abs(axis.y) > 0.99 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0)));
	vec3 tan2 = cross(axis, tan1);

	vec3 ro = CAMERA_POSITION_WORLD;
	vec3 rd = normalize(world_pos - ro);
	vec3 center = origin + axis * (fire_height * 0.5);
	float radius = bound_radius();
	vec3 oc = ro - center;
	float b = dot(oc, rd);
	float c = dot(oc, oc) - radius * radius;
	float disc = b * b - c;
	if (disc <= 0.0) {
		discard;
	}
	float sq = sqrt(disc);
	float t0 = max(-b - sq, 0.0);
	float t1 = -b + sq;
	if (t1 <= t0) {
		discard;
	}

	float dt = (t1 - t0) / float(raymarch_steps);
	float jitter = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	float t = t0 + dt * jitter;
	float t_anim = -TIME * time_scale;

	vec3 acc = vec3(0.0);
	float alpha = 0.0;
	for (int i = 0; i < raymarch_steps; i++) {
		vec3 p = ro + rd * t;
		vec3 rel = p - origin;
		vec3 local_p = vec3(dot(rel, tan1), dot(rel, axis) - fire_height * 0.5, dot(rel, tan2));
		float nh = (local_p.y + fire_height * 0.5) / fire_height;

		vec3 wob = wobble_offset(local_p, t_anim);
		float sdf_dist = fire_sdf(local_p, wob, t_anim);
		float n = get_noise(local_p + wob * 0.7, noise_scale * 0.7, t_anim * 30.0);

		float d = 0.0;
		if (sdf_dist < 0.0) {
			float shaping = 1.0 - smoothstep(noise_threshold * 0.8, noise_threshold * 1.2, n);
			d = clamp(smoothstep(0.0, sharpness_cutoff, -sdf_dist * 0.5 + shaping), 0.0, 1.0);
			d *= 1.0 - pow(smoothstep(0.5, 1.0, nh), 0.333);
			d *= smoothstep(0.7, 0.0, length(local_p.xz) / (fire_width * 0.5));
		}

		float a_step = 1.0 - exp(-d * dt * density);
		vec3 col = mix(color_outer, color_mid, n);
		col = mix(col, color_core, smoothstep(0.7, 1.0, d * core_glow_multiplier));
		col = mix(col, color_smoke, smoothstep(0.6, 1.0, nh * (1.0 - d)));
		acc += col * a_step * (1.0 - alpha);
		alpha += a_step * (1.0 - alpha);
		if (alpha > 0.99) {
			break;
		}
		t += dt;
	}

	float a = clamp(alpha, 0.0, 1.0);
	float depth_raw = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 vpos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	vpos.xyz /= vpos.w;
	a *= clamp(1.0 - smoothstep(vpos.z + proximity_fade_distance, vpos.z, VERTEX.z), 0.0, 1.0);
	if (alpha < 0.1)
		discard;
	ALBEDO = acc * emission_strength;
	ALPHA = a;
}
