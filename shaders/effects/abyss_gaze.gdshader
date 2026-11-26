shader_type canvas_item;

// La mirada del abismo (AbyssStare): el mundo se retuerce, pierde el color hacia un verde enfermo, se
// abre en franjas de color por los bordes y se cierra en túnel. Después quedan las secuelas, más
// flojas, que se van pasando. Va debajo de la interfaz, como el desangrado.

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
// 0..1: la mirada en curso.
uniform float amount : hint_range(0.0, 1.0) = 0.0;
// 0..1: lo que queda después.
uniform float after : hint_range(0.0, 1.0) = 0.0;
// 0..1: el latido (sube de golpe y cae).
uniform float pulse : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - 0.5;
	float r = length(vec2(d.x * SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, d.y));
	float k = max(amount, after * 0.4);
	float t = TIME;
	// El mundo respira y se retuerce; en las secuelas, despacio y apenas.
	vec2 warp = vec2(sin(uv.y * 9.0 + t * 1.3), cos(uv.x * 7.0 - t * 1.1)) * 0.006 * k;
	warp += d * sin(t * (0.9 + 1.2 * amount)) * 0.014 * k;
	// Túnel: los bordes se estiran hacia los ojos que miran.
	vec2 tunnel = -d * smoothstep(0.2, 0.9, r) * (0.05 * amount + 0.02 * amount * pulse);
	vec2 base = clamp(uv + warp + tunnel, vec2(0.001), vec2(0.999));
	float split = (0.003 + 0.012 * r) * k;
	vec3 c;
	c.r = textureLod(screen, clamp(base + d * split, vec2(0.001), vec2(0.999)), 0.0).r;
	c.g = textureLod(screen, base, 0.0).g;
	c.b = textureLod(screen, clamp(base - d * split, vec2(0.001), vec2(0.999)), 0.0).b;
	float grey = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(grey) * vec3(0.78, 0.96, 0.86), k * 0.75);
	float vignette = smoothstep(0.22, 0.95, r) * (0.6 * amount + 0.3 * after) * (0.8 + 0.2 * pulse);
	c = mix(c, c * vec3(0.04, 0.1, 0.08), vignette);
	COLOR = vec4(c, 1.0);
}
