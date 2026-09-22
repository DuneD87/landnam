shader_type spatial;
render_mode cull_disabled;

instance uniform int species = 0;
instance uniform float swim_phase = 0.0;
instance uniform float swim_frequency = 2.0;
// 0 hidden, 1 opaque. Dithered so the body stays in the opaque pass while spawning.
instance uniform float fade = 1.0;

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void vertex() {
	float phase = TIME * swim_frequency + swim_phase - VERTEX.z * 0.8;
	float wave = sin(phase);
	float tail_end = species == 1 ? 4.1 : (species == 2 ? 2.8 : 2.0);
	float t = clamp((VERTEX.z - 0.2) / (tail_end - 0.2), 0.0, 1.0);
	float tail = t * t * (3.0 - 2.0 * t);
	float derivative = 0.22 * (-0.8 * cos(phase) * tail + wave * 6.0 * t * (1.0 - t) / (tail_end - 0.2));
	if (species == 0) {
		VERTEX.x += wave * tail * 0.22;
		NORMAL.z -= derivative * NORMAL.x;
	} else if (species == 3) {
		// Only flippers carry weights; the shell and head remain rigid.
		VERTEX.y += wave * UV.x * 0.12;
		NORMAL.z += 0.096 * cos(phase) * UV.x * NORMAL.y;
	} else {
		VERTEX.y += wave * tail * 0.22;
		NORMAL.z -= derivative * NORMAL.y;
	}
	NORMAL = normalize(NORMAL);
}

void fragment() {
	if (fade < 1.0) {
		ivec2 cell = ivec2(FRAGCOORD.xy) % 4;
		if ((BAYER[cell.x + cell.y * 4] + 0.5) / 16.0 > fade) {
			discard;
		}
	}
	// Mottling, scute pigments and wet-eye roughness are baked in vertex colors.
	// The baker picks sRGB swatches; decode them so black orcas stay black.
	// MSAA extrapolates the color past thin fins; clamp it so pow() never sees a
	// negative and returns NaN.
	vec3 srgb = clamp(COLOR.rgb, 0.0, 1.0);
	ROUGHNESS = clamp(COLOR.a, 0.0, 1.0);
	ALBEDO = mix(srgb / 12.92, pow((srgb + 0.055) / 1.055, vec3(2.4)), step(0.04045, srgb));
	SPECULAR = 0.45;
}
