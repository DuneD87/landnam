#[compute]
#version 450

// Generador ONE-SHOT de la textura 3D de ruido tileable para las nubes volumétricas.
// PlanetAtmosphere lo despacha una sola vez al inicializar; después la textura vive en
// VRAM (128³ RGBA8 ≈ 8.4 MB) y planet_atmosphere.glsl la muestrea con un tap trilinear
// en lugar de calcular FBM en ALU. Canales:
//   R = FBM Perlin-Worley (freq base 4)  → forma general de la nube (algodón con bordes)
//   G = FBM Worley (freq 8)              → reservado (masas/cobertura de dos escalas)
//   B = FBM Worley (freq 16)             → erosión fina de bordes (coliflor)
//   A = FBM Perlin (freq 2)              → reservado (cobertura de gran escala)
// Todas las frecuencias son ENTERAS y las octavas doblan (×2), así cada canal tilea
// perfecto en las 3 dimensiones → el sampler REPEAT nunca muestra costuras.

layout(local_size_x = 4, local_size_y = 4, local_size_z = 4) in;

layout(rgba8, set = 0, binding = 0) uniform restrict writeonly image3D noise_image;

// Hash 3D→3D sobre coordenadas de celda YA envueltas (mod freq): mismas celdas → mismos
// valores a ambos lados del borde del tile.
vec3 _hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

// Worley F1 invertido y tileable: 1 en el centro de cada "burbuja", 0 hacia las fronteras.
float _worley(vec3 uvw, float freq) {
	vec3 id = floor(uvw * freq);
	vec3 f = fract(uvw * freq);
	float min_d2 = 1e9;
	for (int z = -1; z <= 1; z++)
	for (int y = -1; y <= 1; y++)
	for (int x = -1; x <= 1; x++) {
		vec3 offs = vec3(float(x), float(y), float(z));
		// +freq antes del mod para que las celdas -1 envuelvan al otro lado del tile.
		vec3 cell = mod(id + offs + freq, freq);
		vec3 fp = offs + _hash33(cell);
		vec3 d = f - fp;
		min_d2 = min(min_d2, dot(d, d));
	}
	return 1.0 - clamp(sqrt(min_d2), 0.0, 1.0);
}

// Perlin clásico tileable: gradientes unitarios hasheados del lattice envuelto.
float _perlin(vec3 uvw, float freq) {
	vec3 pf = uvw * freq;
	vec3 i = floor(pf);
	vec3 f = fract(pf);
	vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);   // quintic

	// El +0.0001 evita normalize(0) si el hash cae justo en el centro.
	#define GRAD(o) dot(normalize(_hash33(mod(i + o, vec3(freq))) - 0.5 + 0.0001), f - o)
	float g000 = GRAD(vec3(0, 0, 0));
	float g100 = GRAD(vec3(1, 0, 0));
	float g010 = GRAD(vec3(0, 1, 0));
	float g110 = GRAD(vec3(1, 1, 0));
	float g001 = GRAD(vec3(0, 0, 1));
	float g101 = GRAD(vec3(1, 0, 1));
	float g011 = GRAD(vec3(0, 1, 1));
	float g111 = GRAD(vec3(1, 1, 1));
	#undef GRAD

	float v = mix(
		mix(mix(g000, g100, u.x), mix(g010, g110, u.x), u.y),
		mix(mix(g001, g101, u.x), mix(g011, g111, u.x), u.y),
		u.z);
	// v ≈ [-0.7, 0.7] → [0,1].
	return clamp(v * 0.7 + 0.5, 0.0, 1.0);
}

float _worley_fbm(vec3 uvw, float freq, int octaves) {
	float v = 0.0, a = 0.5, norm = 0.0;
	for (int i = 0; i < octaves; i++) {
		v += a * _worley(uvw, freq);
		norm += a;
		freq *= 2.0;
		a *= 0.5;
	}
	return v / norm;
}

float _perlin_fbm(vec3 uvw, float freq, int octaves) {
	float v = 0.0, a = 0.5, norm = 0.0;
	for (int i = 0; i < octaves; i++) {
		v += a * _perlin(uvw, freq);
		norm += a;
		freq *= 2.0;
		a *= 0.5;
	}
	return v / norm;
}

float _remap(float v, float l0, float h0, float l1, float h1) {
	return l1 + (v - l0) * (h1 - l1) / max(h0 - l0, 0.00001);
}

void main() {
	ivec3 texel = ivec3(gl_GlobalInvocationID.xyz);
	ivec3 size = imageSize(noise_image);
	if (any(greaterThanEqual(texel, size))) return;

	vec3 uvw = (vec3(texel) + 0.5) / vec3(size);

	float perlin = _perlin_fbm(uvw, 4.0, 4);
	float worley = _worley_fbm(uvw, 4.0, 3);

	// Perlin-Worley: el worley "recorta" el suelo del perlin → masas algodonosas con
	// bordes definidos en vez de manchas difusas. CARVE controla cuánto muerde el worley:
	// 0 = perlin puro (nubes difusas), 1 = recorte pleno (muy troceado, media baja).
	// Si lo cambias, recuerda que la media de R baja al subirlo → compensar con
	// cloud_coverage en el inspector.
	const float CARVE = 0.4;
	float pw = clamp(_remap(perlin, (1.0 - worley) * CARVE, 1.0, 0.0, 1.0), 0.0, 1.0);

	float w8  = _worley_fbm(uvw, 8.0, 3);
	float w16 = _worley_fbm(uvw, 16.0, 2);
	float p2  = _perlin_fbm(uvw, 2.0, 2);

	imageStore(noise_image, texel, vec4(pw, w8, w16, p2));
}
