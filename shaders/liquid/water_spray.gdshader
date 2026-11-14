shader_type spatial;
// Dibujo de los rociones del agua (OceanSpray): un quad encarado a la cámara por partícula. Con
// streak = 0 es una nube de bruma redonda y deshilachada; con streak > 0 es una gota estirada a lo
// largo de su velocidad. La vida, el tamaño y el azar llegan en INSTANCE_CUSTOM (ver
// water_spray_process.gdshader).
render_mode blend_mix, cull_disabled, unshaded, depth_draw_never, shadows_disabled;

// La misma luz que usa el agua: de noche la espuma no brilla.
global uniform vec3 sky_sun_radiance;
global uniform vec3 sky_moon_radiance;
global uniform vec3 sky_ambient_radiance;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform float brightness = 0.6;
uniform float opacity : hint_range(0.0, 1.0) = 0.5;
// Tamaño al morir respecto al de nacer.
uniform float grow = 2.0;
// Segundos de velocidad que mide la gota a lo largo; 0 = bruma redonda.
uniform float streak = 0.0;
// Metros en los que se funde contra el terreno y los cascos, para no cortar en una línea.
uniform float soft_distance = 0.6;
// Cuánto se deshilacha la nube (0 = disco liso).
uniform float breakup : hint_range(0.0, 1.0) = 0.8;

varying float v_age;
varying float v_seed;
varying float v_view_z;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	v_age = INSTANCE_CUSTOM.y;
	v_seed = INSTANCE_CUSTOM.x;
	float size = INSTANCE_CUSTOM.z * mix(1.0, grow, sqrt(clamp(v_age, 0.0, 1.0)));
	vec3 right;
	vec3 up;
	if (streak > 0.0) {
		vec3 velocity = MODEL_MATRIX[1].xyz;
		float speed = length(velocity);
		vec3 to_camera = normalize(CAMERA_POSITION_WORLD - center);
		up = speed > 0.001 ? velocity / speed : INV_VIEW_MATRIX[1].xyz;
		right = normalize(cross(up, to_camera) + vec3(0.00001)) * size;
		up *= size + speed * streak;
	} else {
		float angle = v_seed * 6.2831853;
		vec3 cam_right = INV_VIEW_MATRIX[0].xyz;
		vec3 cam_up = INV_VIEW_MATRIX[1].xyz;
		right = (cam_right * cos(angle) + cam_up * sin(angle)) * size;
		up = (cam_up * cos(angle) - cam_right * sin(angle)) * size;
	}
	vec4 view = VIEW_MATRIX * vec4(center + right * VERTEX.x + up * VERTEX.y, 1.0);
	v_view_z = view.z;
	POSITION = PROJECTION_MATRIX * view;
}

float spray_hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float spray_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(spray_hash(i), spray_hash(i + vec2(1.0, 0.0)), f.x),
		mix(spray_hash(i + vec2(0.0, 1.0)), spray_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float shape = 1.0 - smoothstep(0.0, 1.0, radius);
	if (streak > 0.0) {
		shape *= shape;
	} else {
		// Dos octavas de ruido, distintas en cada nube, que comen el borde antes que el centro.
		vec2 q = p * 2.2 + vec2(v_seed * 91.7, v_seed * 37.3);
		float cloud = spray_noise(q) * 0.65 + spray_noise(q * 2.6 + 11.0) * 0.35;
		// El ruido se resta del perfil: la nube pierde trozos enteros, no solo se aclara.
		shape = mix(shape * shape, smoothstep(0.0, 0.55, shape * 1.35 - (1.0 - cloud) * 0.95), breakup);
	}
	float life = smoothstep(0.0, 0.08, v_age) * (1.0 - smoothstep(0.3, 1.0, v_age));

	// Profundidad de la escena opaca bajo el píxel, en espacio de vista.
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ndc.z = depth * 2.0 - 1.0;
	#endif
	vec4 scene = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float scene_z = scene.z / scene.w;
	float soft = clamp((v_view_z - scene_z) / max(soft_distance, 0.001), 0.0, 1.0);
	// Pegada a la cámara una nube llena la pantalla: se apaga antes de llegar.
	float near = smoothstep(0.25, 1.4, -v_view_z);

	vec3 light = sky_ambient_radiance + (sky_sun_radiance + sky_moon_radiance) * 0.8;
	ALBEDO = light * brightness;
	ALPHA = COLOR.a * opacity * shape * life * soft * near;
}
