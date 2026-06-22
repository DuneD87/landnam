shader_type spatial;
// Dibujo de los splashes de lluvia: cada partícula se posa sobre el terreno (altura del canal G del
// campo radial de WeatherOcclusionField) y se dibuja como un anillo alineado a la NORMAL del terreno
// (derivada de la pendiente del propio canal G). La animación (crecer + desvanecer) la lleva el
// ParticleProcessMaterial vía scale_curve + color_ramp; aquí solo colocamos/orientamos el quad y
// descartamos donde no hay suelo o hay techo.
render_mode blend_mix, cull_disabled, unshaded, depth_draw_never;

uniform sampler2D albedo_tex : source_color, filter_linear;

// Campo radial compartido con la lluvia: R = altura del techo, G = altura del suelo (normalizadas).
uniform sampler2D field_tex : filter_linear;
uniform vec3 field_center;
uniform vec3 field_x;
uniform vec3 field_z;
uniform vec3 field_up;
uniform float field_half_size = 50.0;
uniform float field_span = 860.0;
uniform float field_below = 60.0;
uniform float field_enabled = 0.0;
// Si el techo queda esta franja (m) por encima del suelo, estamos bajo techo → sin splashes (cuevas).
uniform float occ_margin = 4.0;
// Levanta el anillo un pelín sobre el suelo (a lo largo de la normal) para evitar z-fighting.
uniform float ground_offset = 0.05;
// Cuánto se inclina el anillo hacia la normal del terreno: 0 = plano radial, 1 = pegado a la pendiente.
uniform float normal_strength : hint_range(0.0, 1.0) = 1.0;

varying float v_hidden;

void vertex() {
	vec3 ppos = MODEL_MATRIX[3].xyz;   // posición de la partícula (nace en un disco fino sobre el jugador)
	v_hidden = 1.0;                    // oculto por defecto hasta confirmar suelo al aire libre

	vec3 rel = ppos - field_center;
	float fu = dot(rel, field_x);
	float fw = dot(rel, field_z);
	vec2 uv = vec2(fu, fw) / field_half_size * 0.5 + 0.5;

	vec3 ground_pos = ppos;
	vec3 normal = field_up;   // por defecto plano (arriba radial)
	if (field_enabled > 0.5 && uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
		vec2 hg = textureLod(field_tex, uv, 0.0).rg;
		float ground_n = hg.g;
		float ceil_n = hg.r;
		if (ground_n > 0.001) {   // hay suelo dentro del rango sondeado
			float gh = ground_n * field_span - field_below;
			float ch = ceil_n * field_span - field_below;   // sin techo → -field_below (muy abajo)
			bool under_roof = (ceil_n > 0.001) && (ch > gh + occ_margin);
			if (!under_roof) {
				// Normal del terreno = pendiente del campo de altura (canal G) por diferencias finitas.
				vec2 texel = 1.0 / vec2(textureSize(field_tex, 0));
				float gL = textureLod(field_tex, uv - vec2(texel.x, 0.0), 0.0).g;
				float gR = textureLod(field_tex, uv + vec2(texel.x, 0.0), 0.0).g;
				float gD = textureLod(field_tex, uv - vec2(0.0, texel.y), 0.0).g;
				float gU = textureLod(field_tex, uv + vec2(0.0, texel.y), 0.0).g;
				// Solo si los 4 vecinos tienen suelo (evita normales locas en bordes sin dato).
				if (gL > 0.001 && gR > 0.001 && gD > 0.001 && gU > 0.001) {
					float du = field_half_size * 2.0 * texel.x;   // metros por texel (eje x)
					float dv = field_half_size * 2.0 * texel.y;   // metros por texel (eje z)
					float dhu = (gR - gL) * field_span / (2.0 * du);   // ∂altura/∂u
					float dhv = (gU - gD) * field_span / (2.0 * dv);   // ∂altura/∂w
					normal = normalize(field_up - field_x * dhu - field_z * dhv);
					normal = normalize(mix(field_up, normal, normal_strength));
				}
				ground_pos = field_center + field_x * fu + field_z * fw
					+ field_up * gh + normal * ground_offset;
				v_hidden = 0.0;
			}
		}
	}

	// Quad en el plano perpendicular a la normal del terreno (tangente estable derivada de field_x),
	// con la escala por partícula (la columna del model matrix la fija scale_min/max * scale_curve).
	vec3 tangent = normalize(field_x - normal * dot(field_x, normal));
	vec3 bitangent = cross(normal, tangent);
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 world = ground_pos + VERTEX.x * sx * tangent + VERTEX.y * sy * bitangent;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(world, 1.0));
}

void fragment() {
	if (v_hidden > 0.5) {
		discard;
	}
	ALBEDO = COLOR.rgb;
	ALPHA = texture(albedo_tex, UV).a * COLOR.a;
}
