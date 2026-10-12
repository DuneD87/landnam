// Las runas del engaste del aguante encendidas como medidor del oxígeno (BreathRing): la textura
// son solo las runas, centradas; se encienden desde lo alto en el sentido de las agujas del reloj
// hasta `fill`, con un halo (el mismo dibujo en un mip más borroso) y la banda apenas teñida.
shader_type canvas_item;

uniform float fill : hint_range(0.0, 1.0) = 1.0;
uniform vec4 color : source_color = vec4(0.62, 0.9, 1.0, 1.0);
uniform vec4 warn_color : source_color = vec4(1.0, 0.45, 0.35, 1.0);
// 1 con poco aire: las runas que quedan laten en rojo.
uniform float warn = 0.0;
// Para aparecer y desaparecer (no vale modulate: COLOR ya trae el alfa de la textura).
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
// Radios de la banda de runas, en fracción del lado de la textura.
uniform float band_in = 0.3950;
uniform float band_out = 0.4550;

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p);
	// 0 arriba y creciendo en el sentido de las agujas del reloj (y hacia abajo en pantalla).
	float turn = fract(atan(p.x, -p.y) / TAU + 1.0);
	float soft = 0.004;
	float lit = 1.0 - smoothstep(fill - soft, fill + soft, turn);
	float runes = texture(TEXTURE, UV).a;
	float glow = textureLod(TEXTURE, UV, 2.5).a;
	float band = smoothstep(band_in - 0.003, band_in, r) * (1.0 - smoothstep(band_out, band_out + 0.003, r));
	float beat = warn * (0.5 + 0.5 * sin(TIME * 7.0));
	vec3 tint = mix(color.rgb, warn_color.rgb, beat);
	float a = clamp(runes + glow * 0.9 + band * 0.16, 0.0, 1.0) * lit;
	COLOR = vec4(tint * (1.0 + runes * 0.35), a * alpha);
}
