shader_type spatial;

// Tapa de un miembro cercenado (LimbCutter). COLOR.r va de 0 en el eje del hueso a 1 en el borde
// (la piel) y UV son coordenadas en el plano del corte, en radios. Por anillos: hueso con su
// médula, músculo en haces, grasa y piel, todo húmedo de sangre. Granate oscuro, como la sangre y
// la canal (no un filete de carnicería).

uniform vec3 muscle_color : source_color = vec3(0.16, 0.018, 0.018);
uniform vec3 muscle_light : source_color = vec3(0.28, 0.042, 0.036);
uniform vec3 fat_color : source_color = vec3(0.5, 0.38, 0.27);
uniform vec3 bone_color : source_color = vec3(0.68, 0.58, 0.5);
uniform vec3 marrow_color : source_color = vec3(0.24, 0.035, 0.03);
uniform vec3 clot_color : source_color = vec3(0.08, 0.003, 0.006);
uniform float bone_radius = 0.24;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(7.1, 3.7);
		a *= 0.5;
	}
	return v;
}

// Bordes de celdas: los tabiques entre haces de músculo.
float cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 c = o + vec2(hash(i + o), hash(i + o + 19.3)) - f;
			float d = dot(c, c);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return sqrt(d2) - sqrt(d1);
}

void fragment() {
	float r = clamp(COLOR.r, 0.0, 1.0);
	vec2 p = UV;
	float n = fbm(p * 5.0);
	float wobble = (fbm(p * 2.5 + 11.0) - 0.5) * 0.08;

	// Músculo: haces separados por tabiques claros, más oscuro hacia el hueso.
	float septa = 1.0 - smoothstep(0.0, 0.09, cells(p * 7.0));
	vec3 col = mix(muscle_color, muscle_light, n);
	col = mix(col, muscle_light * 1.15 + vec3(0.04, 0.02, 0.015), septa * 0.3);
	float rough = 0.22 + 0.12 * n;

	// Grasa bajo la piel, en grumos.
	float fat_in = 0.84 + wobble;
	float fat = smoothstep(fat_in - 0.02, fat_in + 0.02, r) * (1.0 - smoothstep(0.95, 0.975, r));
	col = mix(col, fat_color * (0.85 + 0.3 * fbm(p * 14.0)), fat * 0.75);
	rough = mix(rough, 0.32, fat);

	// Piel del borde.
	float skin = smoothstep(0.955, 0.99, r);
	col = mix(col, vec3(0.3, 0.09, 0.075), skin);

	// Hueso y médula en el centro.
	float bone_r = bone_radius + wobble * 0.5;
	float bone = 1.0 - smoothstep(bone_r - 0.015, bone_r + 0.015, r);
	vec3 bone_col = bone_color * (0.85 + 0.2 * fbm(p * 20.0));
	float marrow = 1.0 - smoothstep(bone_r * 0.42, bone_r * 0.55, r);
	bone_col = mix(bone_col, marrow_color * (0.7 + 0.5 * noise(p * 40.0)), marrow);
	col = mix(col, bone_col, bone);
	rough = mix(rough, mix(0.5, 0.3, marrow), bone);

	// Sangre: coágulos oscuros y una película que lo moja todo (menos al hueso limpio del centro).
	float clot = smoothstep(0.55, 0.75, fbm(p * 3.0 + 4.0));
	col = mix(col, clot_color, clot * 0.85 * (1.0 - bone * 0.5));
	col *= mix(0.85, 1.0, n);

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.55;
}
