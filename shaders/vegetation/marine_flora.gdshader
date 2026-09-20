shader_type spatial;
// Flora sumergida: el vaivén es de corriente, no de viento. La onda viaja en una
// dirección fija del espacio local del item (el instanciador alinea la Y local con la
// normal del terreno), así que no necesita saber dónde está el centro del planeta.
render_mode cull_disabled;

uniform float sway_speed = 0.55;
/// Desplazamiento máximo en la punta, en fracción de la altura de la planta.
uniform float sway_amount = 0.14;
/// Altura de la planta, para normalizar el peso del vaivén.
uniform float plant_height = 1.0;
/// Cuánto se rigidiza la base: 1 = lineal, más alto = solo se mueve la punta.
uniform float sway_stiffness = 1.6;
uniform float roughness_value = 0.78;
/// Extremos del tinte por planta: cada instancia cae en un punto entre los dos.
uniform vec3 tint_cool : source_color = vec3(0.82, 0.95, 1.0);
uniform vec3 tint_warm : source_color = vec3(1.1, 0.95, 0.72);
/// Variación de claridad entre plantas, en fracción.
uniform float value_jitter = 0.18;
/// Luz que atraviesa las frondas finas.
uniform float translucency = 0.35;

varying float instance_tone;
varying float instance_value;

float hash(vec3 point) {
	return fract(sin(dot(point, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	float height = clamp(VERTEX.y / max(plant_height, 0.001), 0.0, 1.0);
	float weight = pow(height, sway_stiffness);
	// Fase por posición del mundo: las matas vecinas no ondulan al unísono.
	vec3 origin = MODEL_MATRIX[3].xyz;
	// El mismo origen da el tono: cada instancia tiene su color, sin datos por instancia.
	instance_tone = hash(floor(origin * 7.3));
	instance_value = hash(floor(origin * 7.3) + 11.7);
	float phase = TIME * sway_speed + dot(origin, vec3(0.31, 0.17, 0.23));
	// Dos armónicos: el balanceo largo de la ola y un temblor corto encima.
	float swing = sin(phase) * 0.8 + sin(phase * 2.7 + 1.3) * 0.2;
	float lateral = swing * weight * sway_amount * plant_height;
	VERTEX.x += lateral;
	VERTEX.z += cos(phase * 0.7) * lateral * 0.35;
	// La punta baja al inclinarse, en vez de estirar la planta.
	VERTEX.y -= abs(lateral) * weight * 0.25;
}

void fragment() {
	// Los colores se hornean como muestras sRGB, igual que en la fauna marina.
	vec3 srgb = COLOR.rgb;
	ALBEDO = mix(srgb / 12.92, pow((srgb + 0.055) / 1.055, vec3(2.4)), step(0.04045, srgb));
	// Tinte y claridad propios de la planta: una pradera entera del mismo verde canta.
	ALBEDO *= mix(tint_cool, tint_warm, instance_tone);
	ALBEDO *= 1.0 + (instance_value - 0.5) * 2.0 * value_jitter;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.35;
	BACKLIGHT = ALBEDO * translucency;
}
