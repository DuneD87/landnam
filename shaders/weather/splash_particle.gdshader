shader_type spatial;
// Dibujo de los splashes de lluvia: cada partícula se posa sobre el terreno (altura del canal G del
// campo radial de WeatherOcclusionField) y se dibuja como un anillo alineado a la NORMAL del terreno
// (derivada de la pendiente del propio canal G). La animación (crecer + desvanecer) la lleva el
// ParticleProcessMaterial vía scale_curve + color_ramp; aquí solo colocamos/orientamos el quad y
// descartamos donde no hay suelo o hay techo.
render_mode blend_mix, cull_disabled, unshaded, depth_draw_never;

uniform sampler2D albedo_tex : source_color, filter_linear;

// Luz solar (día/noche + tinte de atardecer) que multiplica el albedo. La empuja WeatherFX cada
// frame, igual que en la lluvia, para que las salpicaduras se oscurezcan de noche. 1,1,1 = día.
uniform vec3 sun_light = vec3(1.0);

// Campo radial compartido con la lluvia: R = altura del techo, G = altura del suelo (normalizadas),
// B,A = normal real del suelo (tangencial en los ejes del campo, [0,1]). repeat_disable: sin wrap
// para no mezclar el borde opuesto de la rejilla al muestrear cerca del filo.
uniform sampler2D field_tex : filter_linear, repeat_disable;
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
// Pendiente máxima (grados) a la que el anillo aún se inclina con el terreno. Por encima, la
// pendiente del campo no es fiable (pared, borde, o escalón de cuantización) y orientaría el
// anillo casi vertical (90°); en ese caso lo dejamos PLANO (arriba radial). Bájalo si aún ves aros
// inclinados raros; súbelo para que sigan mejor las laderas pronunciadas.
uniform float max_slope_deg : hint_range(0.0, 89.0) = 45.0;

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
				// Normal REAL de la superficie (canales B,A): componentes tangenciales en los ejes
				// del campo, codificadas a [0,1]; reconstruimos la vertical. Sustituye la antigua
				// derivada por diferencias finitas del canal de altura, que en suelo plano daba
				// pendientes falsas (cuantización/bordes/filo de la rejilla) → anillos torcidos o
				// a 90°. Ahora la normal viene directa del raycast del suelo, sin esos artefactos.
				vec2 nenc = textureLod(field_tex, uv, 0.0).ba;
				vec3 surf_n = field_x * (nenc.x * 2.0 - 1.0) + field_z * (nenc.y * 2.0 - 1.0);
				surf_n += field_up * sqrt(max(0.0, 1.0 - dot(surf_n, surf_n)));
				surf_n = normalize(surf_n);
				// Salvaguarda: si la superficie real se inclina más de max_slope_deg respecto al
				// arriba radial (talud/pared pronunciada), el anillo cae PLANO en vez de casi vertical.
				if (dot(surf_n, field_up) >= cos(radians(max_slope_deg))) {
					normal = normalize(mix(field_up, surf_n, normal_strength));
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
	ALBEDO = COLOR.rgb * sun_light;
	ALPHA = texture(albedo_tex, UV).a * COLOR.a;
}
