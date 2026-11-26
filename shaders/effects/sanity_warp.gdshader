shader_type canvas_item;

// La cordura muy baja (SanityEffects, desde perturbado): la imagen respira y se queda casi gris. Lee la
// pantalla (una copia del fondo, sin mipmaps: solo se lee el nivel 0), así que solo se enciende cuando
// hace falta; las sombras del borde van aparte y no la leen (sanity.gdshader).

uniform sampler2D screen : hint_screen_texture, filter_linear;
// 0..1: lo hondo que se está desde perturbado.
uniform float disturbed : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - 0.5;
	float t = TIME;
	vec2 warp = vec2(sin(uv.y * 3.0 + t * 0.6), cos(uv.x * 2.5 - t * 0.45)) * 0.004 * disturbed;
	warp += d * sin(t * 0.8) * 0.01 * disturbed;
	vec3 c = textureLod(screen, clamp(uv + warp, vec2(0.001), vec2(0.999)), 0.0).rgb;
	float grey = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(grey) * vec3(0.92, 0.95, 1.0), 0.1 + 0.45 * disturbed);
	COLOR = vec4(c, 1.0);
}
