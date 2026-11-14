shader_type particles;
// Rociones y salpicaduras del agua (OceanSpray). Ninguna partícula nace sola: todas llegan por
// emit_particle con su posición, velocidad, color y CUSTOM, así que aquí solo se integran.
// CUSTOM: x = azar 0..1, y = edad 0..1, z = tamaño (m), w = vida (s).

// Gravedad del sitio (hacia el centro del planeta) y viento, en mundo. Los empuja OceanSpray.
uniform vec3 gravity = vec3(0.0, -9.8, 0.0);
uniform vec3 wind = vec3(0.0);
// Cuánto de la gravedad siente: la bruma casi flota, la gota cae.
uniform float gravity_scale = 1.0;
// Frenado contra el aire (1/s): lleva la velocidad hacia la del viento.
uniform float drag = 1.0;

void start() {
	if (RESTART_CUSTOM) {
		ACTIVE = false;
	}
}

void process() {
	CUSTOM.y += DELTA / max(CUSTOM.w, 0.05);
	if (CUSTOM.y >= 1.0) {
		ACTIVE = false;
	}
	// COLOR.r = cuánto flota la partícula: 0 = gota que cae, 1 = rocío fino que el viento se lleva.
	float floaty = COLOR.r;
	VELOCITY += gravity * (gravity_scale * mix(1.0, 0.3, floaty) * DELTA);
	VELOCITY += (wind - VELOCITY) * min(drag * mix(1.0, 6.0, floaty) * DELTA, 1.0);
	// El dibujo estira la gota a lo largo de su velocidad: viaja en el eje Y de la transformada.
	TRANSFORM[1].xyz = VELOCITY;
}
