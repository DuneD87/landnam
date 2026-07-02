shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, skip_vertex_transform;

// Llama volumétrica de antorcha para planeta esférico. El quad es solo una "ventana": el vertex lo
// convierte en billboard que cubre la esfera envolvente de la llama y el fragment lanza un rayo por
// píxel y lo marcha dentro de un volumen alineado con 'up_axis', acumulando densidad de ruido 3D
// advectado hacia arriba. 'up_axis' lo pone un script por instancia = dirección contra la gravedad.

instance uniform vec3 up_axis = vec3(0.0, 1.0, 0.0);

uniform sampler3D noise_tex : repeat_enable;
uniform float width = 0.13;
uniform float height = 0.35;
uniform float speed = 1.2;
uniform float density = 25.0;
uniform float noise_scale = 4.0;
uniform float sway = 0.45;
uniform float detail = 0.9;
uniform float emission_strength = 2.5;
uniform vec3 hot : source_color = vec3(1.0, 0.85, 0.4);
uniform vec3 cool : source_color = vec3(0.9, 0.2, 0.04);

varying vec3 world_pos;

const int STEPS = 14;

// Billboard esférico centrado en el volumen de la llama: siempre cubre la esfera envolvente,
// también visto desde arriba. Ignora escala/rotación local del mesh (skip_vertex_transform).
void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 axis = normalize(up_axis);
	vec3 center = origin + axis * (height * 0.5);
	float radius = length(vec2(height * 0.5, width * 0.5));
	vec3 cam_right = INV_VIEW_MATRIX[0].xyz;
	vec3 cam_up = INV_VIEW_MATRIX[1].xyz;
	world_pos = center
		+ cam_right * ((UV.x - 0.5) * 2.0 * radius)
		+ cam_up * ((0.5 - UV.y) * 2.0 * radius);
	VERTEX = (VIEW_MATRIX * vec4(world_pos, 1.0)).xyz;
}

// Densidad de la llama en un punto en mundo: la punta se bambolea (anclada en la base), un ruido
// grande dobla el dominio del ruido fino (lenguas en vez de manchas) y el resultado se pasa por un
// smoothstep estrecho para dar bordes definidos. Devuelve la altura normalizada en hn.
float flame_density(vec3 p, vec3 origin, vec3 axis, vec3 tan1, vec3 tan2, out float hn) {
	vec3 rel = p - origin;
	float h = dot(rel, axis);
	hn = h / height;
	if (hn <= 0.0 || hn >= 1.0) {
		return 0.0;
	}
	vec2 rad = vec2(dot(rel, tan1), dot(rel, tan2));
	float k = hn * hn;
	rad -= vec2(sin(TIME * 3.1 + hn * 4.0), cos(TIME * 2.3 + hn * 3.0)) * (sway * width * k);
	float prof = 0.5 * width * smoothstep(0.0, 0.05, hn) * (1.0 - smoothstep(0.15, 1.0, hn));
	if (prof <= 0.001) {
		return 0.0;
	}
	float body = 1.0 - length(rad) / prof;
	if (body <= 0.0) {
		return 0.0;
	}
	vec3 uvw = vec3(rad.x, h - TIME * speed, rad.y) * noise_scale;
	float warp = texture(noise_tex, uvw * 0.4).r - 0.5;
	float n = texture(noise_tex, uvw + vec3(warp * detail)).r;
	return smoothstep(0.30, 0.62, body * (0.25 + 1.3 * n));
}

// Raymarch: interseca la esfera envolvente, marcha STEPS pasos con jitter por píxel (rompe el
// banding) y compone front-to-back. El núcleo denso y bajo tiende a blanco; la punta, a 'cool'.
void fragment() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 axis = normalize(up_axis);
	vec3 tan1 = normalize(cross(axis, abs(axis.y) > 0.99 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0)));
	vec3 tan2 = cross(axis, tan1);

	vec3 ro = CAMERA_POSITION_WORLD;
	vec3 rd = normalize(world_pos - ro);
	vec3 center = origin + axis * (height * 0.5);
	float radius = length(vec2(height * 0.5, width * 0.5));
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

	float dt = (t1 - t0) / float(STEPS);
	float jitter = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	float t = t0 + dt * jitter;

	vec3 acc = vec3(0.0);
	float alpha = 0.0;
	for (int i = 0; i < STEPS; i++) {
		vec3 p = ro + rd * t;
		float hn = 0.0;
		float d = flame_density(p, origin, axis, tan1, tan2, hn);
		if (d > 0.001) {
			vec3 col = mix(hot, cool, smoothstep(0.15, 0.95, hn - d * 0.35));
			col = mix(col, vec3(1.05, 1.0, 0.88), pow(d, 2.0) * (1.0 - hn) * 0.85);
			float da = 1.0 - exp(-d * density * dt);
			acc += col * da * (1.0 - alpha);
			alpha += da * (1.0 - alpha);
		}
		t += dt;
	}
	ALBEDO = acc * emission_strength;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
