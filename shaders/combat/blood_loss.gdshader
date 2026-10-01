shader_type canvas_item;

// Desangrarse (CombatHUD): el mundo pierde color y los bordes se oscurecen en rojo a cada latido.
// Va debajo de la interfaz de combate, así que las barras no se apagan.

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
// 0..1: cuánto se desangra.
uniform float amount : hint_range(0.0, 1.0) = 0.0;
// 0..1: el latido (sube de golpe y cae).
uniform float pulse : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 c = textureLod(screen, SCREEN_UV, 0.0).rgb;
	float grey = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(grey) * vec3(1.04, 0.96, 0.96), amount * 0.8);
	vec2 d = SCREEN_UV - 0.5;
	d.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float r = length(d) * 1.5;
	float vignette = smoothstep(0.35, 1.1, r) * amount * (0.45 + 0.55 * pulse);
	c = mix(c, c * vec3(0.4, 0.04, 0.04), vignette);
	COLOR = vec4(c, 1.0);
}
