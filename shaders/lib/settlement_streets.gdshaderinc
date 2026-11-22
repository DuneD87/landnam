// Las calles y la plaza de las villas cercanas (SettlementStreets): tramos en coordenadas canónicas
// (mundo actual + u_world_offset), así que no hay que moverlos con el origen flotante. El terreno las
// pinta con el material de las sendas (planet_biomes.gdshader) y la hierba no brota encima
// (grass_wind.gdshader).
//   settlement_streets       fila 0: el principio de cada tramo (xyz) y su medio ancho (w);
//                            fila 1: su final (xyz). La plaza es un tramo de un punto con su radio.
//   settlement_street_count  cuántos tramos hay
//   settlement_street_bounds esfera que los abarca todos: fuera de ella no se mira nada, así que sin
//                            una villa cerca no cuesta nada
// Quien lo incluye declara antes global uniform vec3 u_world_offset.

global uniform sampler2D settlement_streets;
global uniform int settlement_street_count;
global uniform vec4 settlement_street_bounds;

// Metros de [p] (canónica) al borde de la calle más cercana: negativo dentro, 1000 lejos de todas.
float settlement_street_edge(vec3 p) {
	if (settlement_street_count <= 0 || distance(p, settlement_street_bounds.xyz) > settlement_street_bounds.w) {
		return 1000.0;
	}
	float best = 1000.0;
	for (int i = 0; i < settlement_street_count; i++) {
		vec4 a = texelFetch(settlement_streets, ivec2(i, 0), 0);
		vec3 b = texelFetch(settlement_streets, ivec2(i, 1), 0).xyz;
		vec3 ab = b - a.xyz;
		float t = clamp(dot(p - a.xyz, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
		best = min(best, distance(p, a.xyz + ab * t) - a.w);
	}
	return best;
}
