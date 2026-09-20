shader_type spatial;
// Polvo en suspensión: una retícula FIJA en coordenadas del mundo. La posición de cada
// mota sale de su celda, así que no se mueve nunca; al desplazarte, lo único que cambia
// es qué celdas quedan alrededor de la cámara. De ahí sale el paralaje, que es la señal
// de profundidad que el agua abierta no tiene. No usa TIME en ninguna parte.
//
// Opacas a propósito: el compositor nieblea a partir del búfer de profundidad, y una
// mota transparente recibiría la niebla de lo que tiene detrás, que a pocos metros la
// borra. Escribiendo profundidad, cada mota recibe la suya y el polvo lejano se disuelve
// en la niebla solo.
render_mode cull_disabled, depth_draw_opaque, unshaded;

/// Lado de la celda, en metros: manda la separación media entre motas.
uniform float cell_size = 0.5;
/// Celdas por eje del bloque que rodea a la cámara. El alcance es la mitad de esto por celda.
uniform int grid_side = 16;
/// Fracción de celdas ocupadas.
uniform float occupancy : hint_range(0.0, 1.0) = 0.5;
uniform float size = 0.011;
/// Color del agua a la profundidad de la cámara, calculado como lo hace la niebla
/// (uw_depth_color). Las motas parten de ese color: son agua un poco más turbia, no
/// puntos blancos. Lo empuja UnderwaterDust cada frame.
uniform vec3 water_color = vec3(0.14, 0.34, 0.38);
/// Margen de claridad alrededor del color del agua. Por debajo de 1 la mota es una
/// sombra de materia; por encima, una partícula iluminada.
uniform vec2 shade_range = vec2(0.55, 2.2);
/// Plano de la línea de flotación, el mismo que usan la superficie y la niebla.
uniform vec3 waterline_point = vec3(0.0);
uniform vec3 waterline_normal = vec3(0.0, 1.0, 0.0);

varying float mote_shade;

float hash(vec3 cell) {
	return fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	int side = max(grid_side, 1);
	int id = INSTANCE_ID;
	vec3 index = vec3(float(id % side), float((id / side) % side), float(id / (side * side)));
	vec3 eye = INV_VIEW_MATRIX[3].xyz;
	// La celda es absoluta: la misma región del mundo da siempre la misma mota.
	vec3 cell = floor(eye / cell_size) + index - float(side / 2);
	vec3 position = (cell + vec3(hash(cell), hash(cell + 7.1), hash(cell + 13.7))) * cell_size;

	float reach = float(side / 2) * cell_size;
	float distance_to_eye = length(position - eye);
	// El polvo solo se ve cerca: más allá, una mota aislada sobre el agua oscura se lee
	// como una estrella. Se apagan encogiendo, porque recortar por opacidad parpadea
	// con motas de dos píxeles. Muy pegadas a la cámara también se encogen, para que
	// ninguna se convierta en un borrón delante de la cara.
	float edge = (1.0 - smoothstep(reach * 0.35, reach * 0.85, distance_to_eye))
			* smoothstep(0.12, 0.45, distance_to_eye);
	float present = step(1.0 - occupancy, hash(cell + 3.3));
	float submerged = 1.0 - step(0.0, dot(position - waterline_point, waterline_normal));
	// Unas más claras y otras más oscuras que el agua: el polvo real no brilla entero.
	mote_shade = mix(shade_range.x, shade_range.y, hash(cell + 31.3));
	// Tamaños desiguales: una retícula de motas idénticas se lee como rejilla.
	float grain = 0.5 + 0.65 * hash(cell + 21.7);
	// Una mota a medio metro no debe ocupar más pantalla que un grano: se le recorta
	// parte del tamaño que le daría la perspectiva.
	float near_cap = mix(0.55, 1.0, smoothstep(0.3, 1.6, distance_to_eye));
	float scale = size * grain * edge * present * submerged * near_cap;

	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			INV_VIEW_MATRIX[0] * scale, INV_VIEW_MATRIX[1] * scale,
			INV_VIEW_MATRIX[2] * scale, vec4(position, 1.0));
}

void fragment() {
	vec2 offset = UV - vec2(0.5);
	if (dot(offset, offset) > 0.25) {
		discard;
	}
	ALBEDO = water_color * mote_shade;
}
