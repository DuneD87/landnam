shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// Gota de sangre (CombatFx): un quad de cara a la cámara con su +Y en la dirección en que va
// (GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY). Lágrima: cabeza redonda delante
// (arriba en el quad) y cola afilada detrás, abombada para que brille mojada.

uniform vec3 color : source_color = vec3(0.45, 0.02, 0.03);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	// p.y = -1 delante (la cabeza), 1 detrás (la cola).
	float head = -0.45;
	float w = p.y < head
		? sqrt(max(0.0, 1.0 - pow((p.y - head) / (1.0 + head), 2.0)))
		: mix(1.0, 0.0, (p.y - head) / (1.0 - head));
	if (abs(p.x) > w * 0.95) {
		discard;
	}
	float across = p.x / max(w, 0.05);
	float tail = clamp((p.y - head) / (1.0 - head), 0.0, 1.0);
	NORMAL = normalize(vec3(across * 0.9, (p.y < head ? -(p.y - head) : 0.0) * 0.6, 1.0));
	ALBEDO = color * (1.0 - 0.35 * tail) * COLOR.rgb;
	ROUGHNESS = 0.12;
	SPECULAR = 0.6;
}
