shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// Gota de sangre (CombatFx): un quad de cara a la cámara con su +Y en la dirección en que va
// (GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY). Lágrima: cabeza redonda delante
// (arriba en el quad) y cola afilada detrás, abombada para que brille mojada. No es pintura: casi
// negra donde es gruesa (el centro de la cabeza), roja donde es fina (el borde y la cola), con un
// brillo pequeño y fuerte de líquido, y a contraluz deja pasar la luz, roja.

uniform vec3 thick_color : source_color = vec3(0.17, 0.004, 0.01);
uniform vec3 thin_color : source_color = vec3(0.48, 0.03, 0.03);

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
	float thickness = sqrt(max(0.0, 1.0 - across * across)) * (1.0 - 0.7 * tail);
	NORMAL = normalize(vec3(across * 0.9, (p.y < head ? -(p.y - head) : 0.0) * 0.6, 1.0));
	ALBEDO = mix(thin_color, thick_color, thickness) * COLOR.rgb;
	ROUGHNESS = 0.05;
	SPECULAR = 0.5;
	BACKLIGHT = thin_color * (1.0 - thickness * 0.7);
}
