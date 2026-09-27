shader_type spatial;
render_mode unshaded, cull_back;

// Sombreado de icono: dos tonos planos, como los iconos dibujados del inventario.
uniform vec4 base_color : source_color = vec4(0.6, 0.6, 0.6, 1.0);
uniform vec3 light_dir = vec3(-0.45, 0.75, 0.5);
uniform float shade = 0.78;

void fragment() {
	vec3 l = normalize((VIEW_MATRIX * vec4(normalize(light_dir), 0.0)).xyz);
	float d = dot(normalize(NORMAL), l);
	float tone = d > 0.05 ? 1.0 : shade;
	// Brillo estrecho para el metal (lo marca base_color.a < 1).
	float glint = base_color.a < 0.99 && d > 0.85 ? 1.15 : 1.0;
	ALBEDO = base_color.rgb * tone * glint;
}
