shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// Gota de sangre (CombatFx): un quad de cara a la cámara con su +Y en la dirección en que va
// (GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY). Cabeza redonda delante (arriba en el
// quad) y, detrás, una cola que cada gota estira a su manera (unas casi redondas, otras hilos
// largos que se van rompiendo), abombada para que brille mojada. No es pintura: roja y viva donde
// es fina (el borde y la cola, que la luz atraviesa), granate oscuro donde es gruesa, con un
// brillo pequeño y fuerte de líquido.

uniform vec3 thick_color : source_color = vec3(0.27, 0.012, 0.014);
uniform vec3 thin_color : source_color = vec3(0.62, 0.045, 0.035);

varying float tail_end;
varying float head_size;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	float id = float(INSTANCE_ID);
	// Dónde acaba la cola (en el quad, -1 delante, 1 detrás): de una gota casi redonda a un hilo.
	tail_end = mix(-0.15, 1.0, pow(hash(id + 0.37), 0.7));
	head_size = mix(0.8, 1.0, hash(id + 5.1));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	// p.y = -1 delante (la cabeza), tail_end detrás (la punta de la cola).
	float head = -0.45;
	float w;
	if (p.y < head) {
		w = sqrt(max(0.0, 1.0 - pow((p.y - head) / (1.0 + head), 2.0)));
	} else {
		float t = clamp((p.y - head) / max(tail_end - head, 0.05), 0.0, 1.0);
		// Se afina deprisa al salir de la cabeza y sigue como un hilo.
		w = p.y > tail_end ? 0.0 : mix(1.0, 0.18, sqrt(t)) * (1.0 - t * t);
	}
	w *= head_size;
	if (abs(p.x) > w * 0.95) {
		discard;
	}
	float across = p.x / max(w, 0.05);
	float tail = clamp((p.y - head) / max(1.0 - head, 0.05), 0.0, 1.0);
	float thickness = sqrt(max(0.0, 1.0 - across * across)) * (1.0 - 0.8 * tail);
	NORMAL = normalize(vec3(across * 0.9, (p.y < head ? -(p.y - head) : 0.0) * 0.6, 1.0));
	ALBEDO = mix(thin_color, thick_color, thickness) * COLOR.rgb;
	ROUGHNESS = 0.04;
	SPECULAR = 0.6;
	BACKLIGHT = thin_color * (1.0 - thickness * 0.6);
}
