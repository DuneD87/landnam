// Líquido de una orbe de vida o aguante (VitalOrb): una esfera de cristal llena hasta `fill`, con
// la superficie ondulando, remolinos dentro, más oscura hacia el borde, el tramo perdido (`trail`)
// por encima en otro color y un brillo de cristal arriba a la izquierda. También hace de media
// orbe (half_orb), que se llena desde la base plana.
shader_type canvas_item;

uniform vec4 liquid_color : source_color = vec4(0.7, 0.08, 0.06, 1.0);
uniform vec4 deep_color : source_color = vec4(0.22, 0.01, 0.02, 1.0);
uniform vec4 trail_color : source_color = vec4(0.86, 0.66, 0.3, 1.0);
uniform float fill : hint_range(0.0, 1.0) = 1.0;
uniform float trail : hint_range(0.0, 1.0) = 0.0;
// Aclara el líquido (latido, golpe) y lo apaga (agotado).
uniform float glow : hint_range(0.0, 1.0) = 0.0;
uniform float dim : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D noise : repeat_enable, filter_linear;
// 1: media orbe (la de la cordura). El rectángulo es solo la mitad de arriba, con el centro abajo.
uniform float half_orb = 0.0;

void fragment() {
	vec2 p = vec2(UV.x * 2.0 - 1.0, mix(UV.y * 2.0 - 1.0, UV.y - 1.0, half_orb));
	float r = length(p);
	float edge = fwidth(r) * 1.5;
	float inside = 1.0 - smoothstep(1.0 - edge, 1.0, r);

	// La superficie ondula, salvo vacía o llena del todo.
	float t = TIME;
	float calm = step(0.002, fill) * step(fill, 0.998);
	float wave = (sin(UV.x * 9.0 + t * 2.2) * 0.012 + sin(UV.x * 17.0 - t * 3.1) * 0.006) * calm;
	float level = 1.0 - fill + wave;
	float soft = 0.006;
	float in_liquid = smoothstep(level - soft, level + soft, UV.y);
	float trail_level = 1.0 - max(trail, fill) + wave;
	float in_trail = smoothstep(trail_level - soft, trail_level + soft, UV.y) * (1.0 - in_liquid);

	// Remolinos: dos capas de ruido que se mueven en sentidos distintos.
	float n = texture(noise, UV * 1.2 + vec2(t * 0.03, -t * 0.05)).r * 0.6
		+ texture(noise, UV * 2.3 - vec2(t * 0.04, t * 0.02)).r * 0.4;
	vec3 liquid = mix(deep_color.rgb, liquid_color.rgb, clamp(n * 1.3 - 0.25 + (1.0 - UV.y) * 0.35, 0.0, 1.0));
	// Línea clara en la superficie.
	liquid += liquid_color.rgb * exp(-abs(UV.y - level) * 160.0) * 0.7 * calm;

	vec3 color = vec3(0.025, 0.027, 0.032);
	color = mix(color, trail_color.rgb * 0.75, in_trail);
	color = mix(color, liquid, in_liquid);
	// Esfera: más oscura hacia el borde.
	color *= mix(1.0, 0.4, smoothstep(0.3, 1.0, r));
	float gray = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(color, vec3(gray) * 0.55, dim);
	color *= 1.0 + glow * 0.6;
	// Brillo del cristal, arriba a la izquierda.
	float spec = smoothstep(0.45, 0.0, length((p - vec2(-0.34, -0.46)) * vec2(1.0, 1.7)));
	color += vec3(spec * 0.16);
	COLOR = vec4(color, inside);
}
