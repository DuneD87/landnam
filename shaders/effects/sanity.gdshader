shader_type canvas_item;
render_mode blend_mul;

// La cordura baja (SanityEffects), lo barato: sombras que se arrastran desde los bordes de la vista y, a
// ratos, una figura oscura que asoma en el borde. Multiplica lo que hay debajo, así que no lee la pantalla
// (sin copia del fondo): el centro de la vista sale en blanco sin calcular nada. Lo que sí la lee (la
// imagen que respira y pierde el color) va aparte, en sanity_warp.gdshader, solo desde perturbado.

// 0..1: lo hondo que se está (desde inquieto hasta sin cordura).
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
// La figura del borde: dónde (0..1 de pantalla, los pies) y cuánto se ve.
uniform vec2 figure_uv = vec2(0.07, 0.55);
uniform float figure_alpha : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += noise(p) * a;
		p = p * 2.03 + 7.1;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 da = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);
	float r = length(da) / length(vec2(0.5 * aspect, 0.5));
	float t = TIME;
	float keep = 1.0;
	// Sombras desde los bordes, más adentro cuanto peor. Dentro del círculo limpio, ni se calculan.
	float reach = mix(0.95, 0.55, intensity);
	if (r > reach - 0.35) {
		float angle = atan(da.y, da.x);
		float n = fbm(vec2(angle * 2.5 + sin(t * 0.07) * 2.0, r * 3.0 - t * 0.12));
		float edge = smoothstep(reach - 0.15, reach + 0.25, r + (n - 0.5) * 0.35);
		keep = 1.0 - edge * (0.35 + 0.6 * intensity) * 0.94;
	}
	// La figura: una silueta alta y borrosa (cabeza y cuerpo), oscura.
	if (figure_alpha > 0.0 && abs(uv.x - figure_uv.x) < 0.06 && uv.y > figure_uv.y - 0.26 && uv.y < figure_uv.y + 0.04) {
		vec2 p = vec2((uv.x - figure_uv.x) * aspect, uv.y - figure_uv.y);
		p.x += (noise(vec2(uv.y * 30.0, t * 3.0)) - 0.5) * 0.006;
		float head = 1.0 - smoothstep(0.018, 0.03, length((p - vec2(0.0, -0.2)) * vec2(1.0, 0.85)));
		float body = 1.0 - smoothstep(0.02, 0.045, length((p - vec2(0.0, -0.09)) * vec2(1.0, 0.42)));
		float shape = max(head, body) * (0.75 + 0.25 * noise(p * 60.0 + t));
		keep *= 1.0 - shape * figure_alpha * 0.96;
	}
	COLOR = vec4(vec3(keep), 1.0);
}
