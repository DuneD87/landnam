// Fondo de las pantallas de Saga que se abren sobre la partida (equipo): el mundo desenfocado,
// oscurecido y con viñeta, para que las ventanas se lean encima sin perderlo de vista.
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
// Nivel de mipmap del desenfoque (cada uno, la mitad de resolución).
uniform float blur : hint_range(0.0, 7.0) = 3.5;
uniform vec4 tint : source_color = vec4(0.02, 0.022, 0.027, 1.0);
// Cuánto tiñe en el centro y cuánto más en los bordes.
uniform float darken : hint_range(0.0, 1.0) = 0.62;
uniform float vignette : hint_range(0.0, 1.0) = 0.3;

void fragment() {
	// Cuatro muestras desplazadas medio texel del mip quitan los bloques del desenfoque.
	vec2 texel = vec2(exp2(blur)) / vec2(textureSize(screen_texture, 0));
	vec3 color = vec3(0.0);
	color += textureLod(screen_texture, SCREEN_UV + texel * vec2(-0.5, -0.5), blur).rgb;
	color += textureLod(screen_texture, SCREEN_UV + texel * vec2(0.5, -0.5), blur).rgb;
	color += textureLod(screen_texture, SCREEN_UV + texel * vec2(-0.5, 0.5), blur).rgb;
	color += textureLod(screen_texture, SCREEN_UV + texel * vec2(0.5, 0.5), blur).rgb;
	color *= 0.25;
	// Desaturado: el color del mundo no compite con el bronce.
	color = mix(color, vec3(dot(color, vec3(0.299, 0.587, 0.114))), 0.35);
	float edge = smoothstep(0.25, 0.95, length((SCREEN_UV - 0.5) * vec2(1.25, 1.0)) * 1.4);
	COLOR = vec4(mix(color, tint.rgb, clamp(darken + edge * vignette, 0.0, 1.0)), 1.0);
}
