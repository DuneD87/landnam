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
	vec3 liquid = mix(deep_color.rgb, liquid_color.rgb,
		clamp(0.48 + n * 0.38 + (1.0 - UV.y) * 0.18, 0.0, 1.0));
	// Línea clara en la superficie.
	liquid += liquid_color.rgb * exp(-abs(UV.y - level) * 160.0) * 0.7 * calm;

	vec3 color = vec3(0.035, 0.045, 0.055);
	color = mix(color, trail_color.rgb * 0.75, in_trail);
	color = mix(color, liquid, in_liquid);
	// Volumen de la lente: iluminación amplia y borde oscuro, también por encima del líquido.
	vec3 normal = vec3(p, sqrt(max(1.0 - dot(p, p), 0.0)));
	vec3 light = normalize(vec3(-0.45, -0.55, 1.0));
	float facing = max(dot(normal, light), 0.0);
	color *= mix(1.0, 0.35, smoothstep(0.45, 1.0, r)) * (0.72 + facing * 0.45);
	float gray = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(color, vec3(gray) * 0.55, dim);
	color *= 1.0 + glow * 0.6;
	// Reflejo de estudio y filo curvo: el cristal tiene profundidad sin ocultar la superficie.
	float spec = pow(facing, 24.0);
	float glint = 1.0 - smoothstep(0.0, 0.2, length((p - vec2(-0.3, -0.45)) * vec2(1.0, 1.8)));
	float rim = exp(-abs(r - 0.89) * 95.0);
	float upper_left = max(dot(p / max(r, 0.001), normalize(vec2(-0.5, -0.85))), 0.0);
	color += vec3(0.75, 0.84, 0.9) * (spec * 0.3 + glint * 0.2 + rim * upper_left * 0.25);
	COLOR = vec4(color, inside);
}
