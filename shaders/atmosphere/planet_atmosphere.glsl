#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict image2D color_image;
layout(set = 0, binding = 1) uniform sampler2D depth_texture;

// UBO en vez de SSBO: todos los hilos leen los mismos parámetros, así que van por la
// constant cache. El tamaño (24) debe coincidir con PARAM_VEC4_COUNT en planet_atmosphere.gd.
layout(set = 0, binding = 2, std140) uniform ParamsBuffer {
	vec4 data[24];
} params_buffer;

// Rejilla de oclusión radial del WeatherOcclusionField (R = altura del techo de cueva). La niebla
// la usa para no rellenar el aire bajo techo. Si la oclusión está apagada (P(19).w < 0.5) NO se
// muestrea; se bindea aquí una textura cualquiera solo para satisfacer el uniform set.
layout(set = 0, binding = 3) uniform sampler2D occ_height_tex;

// Ruido 3D tileable precalculado (cloud_noise_gen.glsl, generado una vez al inicializar):
// R = Perlin-Worley base, G = Worley medio (reservado), B = Worley fino (erosión),
// A = Perlin de gran escala (reservado). Sampler LINEAR + REPEAT: un tap trilinear
// sustituye a los FBM en ALU de las nubes.
layout(set = 0, binding = 4) uniform sampler3D cloud_noise_tex;

#define P(i) params_buffer.data[i]

// El canal R se horneó con frecuencia base 4 por tile → 1 unidad de noise_pos (la longitud
// de onda del antiguo FBM) equivale a 1/4 de tile, y el patrón se repite cada 4 unidades.
const float CLOUD_NOISE_INV_TILE = 0.25;

const float EPSILON   = 0.000001;
const float MAX_FLOAT = 3.402823466e+38;
const float PI        = 3.14159265359;

// Atmósfera — baja a 6/6 para rendimiento, sube a 16/12 para menos bandas.
const int NUM_IN_SCATTER_POINTS    = 16;
const int NUM_OPTICAL_DEPTH_POINTS = 12;

// Nubes — los pasos de marcha ahora se controlan desde el inspector (PlanetAtmosphere)
// vía P(15): .x = view steps, .y = light steps, .z = shadow steps. Cada lectura va con
// clamp(.., 1, 64) para evitar /0 y bucles runaway. Rango útil: view 8-32, light 3-6,
// shadow 6-12. Más pasos = mejor calidad, más coste.

float cloud_underside_darkening(
	vec3 p,
	vec3 planet_center,
	float cloud_min_r,
	float cloud_max_r
) {
	float thickness = max(cloud_max_r - cloud_min_r, 0.001);
	float h = clamp((length(p - planet_center) - cloud_min_r) / thickness, 0.0, 1.0);

	// 1 abajo, 0 arriba.
	float lower_part = 1.0 - smoothstep(0.15, 0.75, h);

	// Valor de prueba visible.
	// 0.55 = bastante visible. Luego puedes subirlo a 0.70 / 0.80.
	return mix(1.0, 0.25, lower_part);
}

mat4 get_inv_projection() {
	return mat4(P(1), P(2), P(3), P(4));
}

vec3 view_to_world_dir(vec3 view_dir) {
	vec3 bx = P(5).xyz;
	vec3 by = P(6).xyz;
	vec3 bz = P(7).xyz;
	return bx * view_dir.x + by * view_dir.y + bz * view_dir.z;
}

vec3 reconstruct_view_position(vec2 uv, float depth) {
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
	vec4 view = get_inv_projection() * vec4(ndc, 1.0);
	if (abs(view.w) > EPSILON) {
		view.xyz /= view.w;
	}
	return view.xyz;
}

// Devuelve (dst_to_sphere, dst_through_sphere). Si no impacta: (MAX, 0).
vec2 ray_sphere(vec3 center, float radius, vec3 ro, vec3 rd) {
	vec3 oc = ro - center;
	float b = dot(oc, rd);
	float c = dot(oc, oc) - radius * radius;
	float h = b * b - c;
	if (h < 0.0) return vec2(MAX_FLOAT, 0.0);
	h = sqrt(h);
	float t0 = -b - h;
	float t1 = -b + h;
	if (t1 < 0.0) return vec2(MAX_FLOAT, 0.0);
	float dst_to = max(t0, 0.0);
	return vec2(dst_to, t1 - dst_to);
}


// ===== NUBES VOLUMÉTRICAS =====

float _hash3f(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float _vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(_hash3f(i),               _hash3f(i + vec3(1,0,0)), u.x),
		    mix(_hash3f(i + vec3(0,1,0)), _hash3f(i + vec3(1,1,0)), u.x), u.y),
		mix(mix(_hash3f(i + vec3(0,0,1)), _hash3f(i + vec3(1,0,1)), u.x),
		    mix(_hash3f(i + vec3(0,1,1)), _hash3f(i + vec3(1,1,1)), u.x), u.y),
		u.z);
}

// FBM normalizado: devuelve ~[0,1] independientemente del nº de octavas. Desde que las
// nubes muestrean la textura 3D precalculada, solo lo usa la niebla a ras de suelo.
float _fbm(vec3 p, int octaves) {
	float v = 0.0, a = 0.5, norm = 0.0;
	for (int i = 0; i < 4; i++, a *= 0.5) {
		if (i >= octaves) break;
		v += a * _vnoise(p);
		norm += a;
		p = p * 2.1 + vec3(1.7, 9.2, 3.4);
	}
	return v / max(norm, EPSILON);
}

float cloud_sun_visibility(
	vec3 p,
	vec3 sun_dir,
	vec3 planet_center,
	float planet_radius,
	float softness
) {
	vec3 oc = p - planet_center;

	// Si proj < 0, el punto está en el lado opuesto al sol.
	float proj = dot(oc, sun_dir);

	// Distancia del punto al eje de la sombra cilíndrica del planeta.
	vec3 closest = oc - sun_dir * proj;
	float axis_dist = length(closest);

	// Dentro del cilindro de sombra: oscuro.
	float visibility = smoothstep(
		planet_radius - softness,
		planet_radius + softness,
		axis_dist
	);

	// En el lado diurno no debe bloquearse.
	if (proj > 0.0) {
		visibility = 1.0;
	}

	return visibility;
}

// edge_soft: anchura del borde del umbral. Los marches de vista/luz pasan la del inspector
// (P(10).w); el de sombra al suelo la pasa ensanchada ×4, porque su jitter por píxel sobre
// una densidad casi binaria produce grano en el terreno (varianza alta entre píxeles
// vecinos) — con el borde ancho el campo es suave, el grano desaparece y la sombra gana
// penumbra blanda.
float sample_cloud_density(
	vec3 p, vec3 planet_center,
	float cloud_min_r, float cloud_max_r,
	float coverage, float density_scale, float noise_scale,
	float edge_soft
) {
	vec3 local = p - planet_center;
	float dist = length(local);

	if (dist < cloud_min_r || dist > cloud_max_r) {
		return 0.0;
	}

	vec3 dir = local / max(dist, EPSILON);

	float thickness = max(cloud_max_r - cloud_min_r, 0.001);
	float h = clamp((dist - cloud_min_r) / thickness, 0.0, 1.0);

	float height_grad =
		smoothstep(0.0, 0.2, h) *
		smoothstep(1.0, 0.5, h);

	// noise_scale ahora actúa como frecuencia alrededor del planeta.
	// Valores típicos: 8 - 40.
	float reference_r = max((cloud_min_r + cloud_max_r) * 0.5, 1.0);
	float freq = max(noise_scale, 0.001);

	// Ruido anclado al planeta, no a la cámara.
	vec3 noise_pos = (local / reference_r) * freq;

	// Variación vertical radial. Valor pequeño (0.5–1.0) evita deformación al mover la cámara.
	noise_pos += dir * (h * 0.8);

	// Movimiento de viento: P(14).xyz = dirección (normalizada), P(14).w = tiempo * velocidad.
	noise_pos += P(14).xyz * P(14).w;

	// UN tap trilinear a la textura 3D sustituye a los dos FBM en ALU. Todos los marches
	// (vista, luz, sombra) muestrean la misma densidad: sombras exactas con lo visible.
	vec4 nz = texture(cloud_noise_tex, noise_pos * CLOUD_NOISE_INV_TILE);

	// Forma (R = Perlin-Worley, masas grandes) + detalle (B = Worley fino) mezclados ANTES
	// del umbral: el detalle rompe el borde de las masas sin destruir su silueta.
	float sample_v = mix(nz.r, nz.b, 0.25);

	// Umbral smoothstep (estilo sky-sorta): interior SÓLIDO y borde definido pero suave.
	// El max(0, ruido - umbral) lineal de antes dejaba casi todo el volumen a densidad
	// ~0 → nubes traslúcidas sin silueta, con cualquier ruido. edge_soft = anchura del
	// borde: bajo = recortado/duro, alto = algodonoso difuso.
	float inv_cov = 1.0 - coverage;
	float density = smoothstep(inv_cov - edge_soft, inv_cov + edge_soft, sample_v);

	return density * height_grad * density_scale;
}

float hg_phase(float cos_theta, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (4.0 * PI * pow(max(1.0 + g2 - 2.0 * g * cos_theta, 0.001), 1.5));
}

float cloud_light_od(
	vec3 p, vec3 sun_dir,
	vec3 planet_center, float cloud_min_r, float cloud_max_r,
	float coverage, float density_scale, float noise_scale
) {
	vec2 hit = ray_sphere(planet_center, cloud_max_r, p, sun_dir);
	if (hit.y <= 0.0) return 0.0;
	int light_steps = clamp(int(P(15).y), 1, 64);
	float step_sz = hit.y / float(light_steps);
	float od = 0.0;
	float edge_soft = clamp(P(10).w, 0.01, 0.5);
	vec3 lp = p + sun_dir * (step_sz * 0.5);
	for (int i = 0; i < light_steps; i++) {
		od += sample_cloud_density(lp, planet_center, cloud_min_r, cloud_max_r,
		                           coverage, density_scale, noise_scale, edge_soft) * step_sz;
		lp += sun_dir * step_sz;
	}
	return od;
}

// Sombra de nube proyectada sobre la superficie: transmitancia de la luz solar a
// través de la capa de nube, medida desde un punto del terreno hacia el sol.
// Solo marcha el segmento del rayo que cruza la cáscara [cloud_min_r, cloud_max_r].
float cloud_shadow_transmittance(
	vec3 p, vec3 sun_dir,
	vec3 planet_center, float cloud_min_r, float cloud_max_r,
	float coverage, float density_scale, float noise_scale, float absorption,
	float jitter
) {
	vec2 outer = ray_sphere(planet_center, cloud_max_r, p, sun_dir);
	if (outer.y <= 0.0) return 1.0;                  // el rayo al sol no alcanza la capa

	// Punto bajo la base de las nubes: inner.y = salida de la esfera interior = base
	// de la cáscara. Punto ya dentro de la cáscara: sin impacto interior, arranca en p.
	vec2 inner = ray_sphere(planet_center, cloud_min_r, p, sun_dir);
	float t_start = inner.y > 0.0 ? inner.y : 0.0;
	float seg = outer.y - t_start;
	if (seg <= 0.001) return 1.0;

	// Borde ensanchado ×4 SOLO para la sombra: con el umbral casi binario de la nube visible,
	// el jitter por píxel de esta marcha producía grano en el terreno (píxeles vecinos
	// atravesaban cantidades de nube muy distintas). El campo suavizado mata esa varianza
	// y de paso da penumbra blanda a la sombra. La nube visible no cambia.
	float edge_soft = min(clamp(P(10).w, 0.01, 0.5) * 4.0, 0.5);
	int shadow_steps = clamp(int(P(15).z), 1, 64);
	float step_sz = seg / float(shadow_steps);
	float od = 0.0;
	vec3 lp = p + sun_dir * (t_start + step_sz * (0.5 + jitter));
	for (int i = 0; i < shadow_steps; i++) {
		od += sample_cloud_density(lp, planet_center, cloud_min_r, cloud_max_r,
		                           coverage, density_scale, noise_scale, edge_soft) * step_sz;
		lp += sun_dir * step_sz;
	}
	return exp(-od * absorption);
}

void march_clouds(
	vec3 ro, vec3 rd, float max_dist,
	vec3 planet_center, float cloud_min_r, float cloud_max_r,
	float density_scale, float coverage,
	float absorption, float g, float noise_scale,
	vec3 sun_dir, float sun_intensity, float planet_radius,
	float jitter,
	out vec3 out_color, out float out_trans
) {
	out_color = vec3(0.0);
	out_trans = 1.0;

	vec2 outer = ray_sphere(planet_center, cloud_max_r, ro, rd);
	if (outer.y <= 0.0) return;

	float t0 = outer.x;
	float t1 = outer.x + outer.y;

	// Recortar por la esfera interior (base de la capa de nubes).
	// - Cámara DENTRO de la esfera interior (en superficie): inner.x == 0, marchar desde la salida.
	// - Cámara FUERA de la esfera interior: cortar t1 antes de entrar en ella.
	vec2 inner = ray_sphere(planet_center, cloud_min_r, ro, rd);

	if (inner.y > 0.0) {
		float ro_r = length(ro - planet_center);

		// Cámara debajo de la base de las nubes: empezar al salir de la esfera interior.
		if (ro_r < cloud_min_r) {
			t0 = max(t0, inner.x + inner.y);
		}
		// Cámara fuera de la esfera interior: cortar antes de entrar en ella.
		else {
			t1 = min(t1, inner.x);
		}
	}

	t0 = max(t0, 0.0);
	t1 = min(t1, max_dist);
	if (t1 <= t0 + 0.001) return;

	int cloud_steps = clamp(int(P(15).x), 1, 64);
	float step_size = (t1 - t0) / float(cloud_steps);
	float big_step  = step_size * 2.0;   // pasos grandes en aire limpio
	float cos_theta = dot(rd, sun_dir);
	float phase = hg_phase(cos_theta, g);
	float edge_soft = clamp(P(10).w, 0.01, 0.5);   // anchura de borde del inspector

	// Empty-space skipping: con la textura 3D la muestra completa cuesta un solo tap, así
	// que hace ella misma de sonda. En aire limpio avanzamos con pasos grandes; dentro de
	// la nube, finos. El presupuesto extra cubre el caso de rayos mayormente vacíos.
	int MAX_MARCH_ITERS = cloud_steps + cloud_steps / 2;
	float t = t0 + step_size * jitter;

	for (int i = 0; i < MAX_MARCH_ITERS && t < t1; i++) {
		vec3 p = ro + rd * t;

		float d = sample_cloud_density(p, planet_center, cloud_min_r, cloud_max_r,
		                               coverage, density_scale, noise_scale, edge_soft);
		if (d <= 0.0001) {
			t += big_step;
			continue;
		}

		{
			float l_od = cloud_light_od(p, sun_dir, planet_center, cloud_min_r, cloud_max_r,
										coverage, density_scale, noise_scale);

			float shadow_softness = max(cloud_max_r - cloud_min_r, planet_radius * 0.005);

			float shadow = cloud_sun_visibility(
				p,
				sun_dir,
				planet_center,
				planet_radius,
				shadow_softness
			);

			float beer   = exp(-l_od * absorption);
			float powder = 1.0 - exp(-d * step_size * absorption * 2.0);

			float direct_light = beer * powder * 2.0 * phase * shadow;
			float ambient_light = 0.10 * shadow;
			float night_light = 0.0;

			// Oscurecimiento de la parte inferior de la nube
			float underside = cloud_underside_darkening(
				p,
				planet_center,
				cloud_min_r,
				cloud_max_r
			);

			// Gradiente día/noche y tinte de atardecer: sincronizan las nubes con la atmósfera.
			vec3 to_cloud = normalize(p - planet_center);
			float sun_dot_c = dot(to_cloud, sun_dir);
			float day_night = smoothstep(-0.15, 0.15, sun_dot_c);

			// Tinte cálido del terminador SOLO sobre la luz DIRECTA (la del sol, que al rasar la
			// atmósfera se enrojece). El ambiente (relleno difuso) queda neutro. Así se auto-regula:
			// el cielo despejado al atardecer glow naranja (domina la directa), pero una nube de
			// tormenta —gruesa, con la directa apagada por su grosor/albedo— se queda gris en vez de
			// teñirse de naranja falso. Sin parámetro por evento.
			float sunset_f = 1.0 - smoothstep(0.0, 0.3, abs(sun_dot_c));
			vec3 sunset_tint = mix(vec3(1.0), vec3(3.0, 0.45, 0.05), sunset_f);

			vec3 lit = (vec3(direct_light) * sunset_tint + vec3(ambient_light)) * sun_intensity
			           + vec3(night_light);
			vec3 lighting = lit * underside * day_night;

			// Albedo de la nube (P(23).z): su reflectividad. 1 = brillo pleno (nube blanca); valores
			// bajos la oscurecen hacia un gris de tormenta. Multiplica TODA la radiancia (directa +
			// ambiente), así baja del suelo ambiental que la opacidad por sí sola no podía rebajar.
			// Independiente de cloud_absorption (opacidad) y de cloud_shadow_strength (sombra al suelo).
			lighting *= P(23).z;

			// Destello de rayo (P(9).w, lightning_flash): emisión breve DENTRO de la nube. Va después
			// del albedo (una nube de tormenta oscura igual fogonea) y del gradiente día/noche (el rayo
			// ilumina la nube también de noche, cuando más luce). Se acumula como el resto de la
			// radiancia → las nubes densas destellan más. Tinte azul-blanco; 12.0 = fuerza (a ojo).
			lighting += vec3(0.7, 0.8, 1.0) * (P(9).w * 12.0);

			float s_trans = exp(-d * step_size * absorption);

			out_color += out_trans * (1.0 - s_trans) * lighting;
			out_trans *= s_trans;

			if (out_trans < 0.005) { out_trans = 0.0; break; }
		}
		t += step_size;
	}
}


// ===== NIEBLA A RAS DE SUELO =====
// Capa volumétrica baja e independiente de las nubes. La densidad la modula un ruido de
// gran escala advectado por el viento (P(18).y), de modo que los bancos viajan
// horizontalmente y "se ven venir de lejos". Es densa abajo y se desvanece hacia arriba,
// así que se origina pegada al suelo en vez de bajar del cielo.

// Setup de la oclusión de cueva, invariante a lo largo del rayo: se construye UNA vez por
// píxel en march_fog en lugar de desempaquetar P() y llamar a textureSize en cada muestra.
struct FogOcclusion {
	bool  enabled;
	vec3  center;
	vec3  x_axis;
	vec3  z_axis;
	vec3  up;
	float inv_half;   // 1 / semiancho de la rejilla
	float span;
	float below;
	float margin;
	float inv_soft;   // 1 / metros de difuminado del borde
	float step_uv;    // separación de las 9 muestras del PCF, en uv
};

FogOcclusion make_fog_occlusion() {
	FogOcclusion o;
	o.enabled = P(19).w > 0.5;
	o.center  = P(19).xyz;
	o.x_axis  = P(20).xyz;
	o.z_axis  = P(21).xyz;
	o.up      = P(22).xyz;
	o.span    = P(21).w;
	o.below   = P(22).w;
	o.margin  = P(23).x;
	float occ_half = max(P(20).w, EPSILON);
	float occ_soft = max(P(23).y, 0.5);   // metros de difuminado del borde (horizontal + vertical)
	o.inv_half = 1.0 / occ_half;
	o.inv_soft = 1.0 / occ_soft;
	// Separación de las 9 muestras: occ_soft metros, con un téxel como mínimo. La rejilla
	// va de -1..1 en u → uv = u*0.5+0.5, así que 1 uv equivale a 2*occ_half metros.
	vec2 res = vec2(textureSize(occ_height_tex, 0));
	o.step_uv = max(occ_soft * 0.5 * o.inv_half, 1.0 / max(res.x, res.y));
	return o;
}

float sample_fog_density(
	vec3 p, vec3 planet_center,
	float fog_min_r, float fog_max_r,
	float coverage, float noise_scale, vec3 wind_dir, float wind_offset,
	FogOcclusion occ
) {
	vec3 local = p - planet_center;
	float dist = length(local);
	if (dist < fog_min_r || dist > fog_max_r) {
		return 0.0;
	}

	// Oclusión de cueva: si el punto cae dentro de la rejilla del WeatherOcclusionField y queda
	// por debajo del techo (roca) detectado sobre el jugador, aquí no hay niebla (estás en cueva).
	// PCF 3x3: promediamos el aporte de oclusión de 9 muestras separadas occ_soft metros, así el
	// borde (boca de cueva) se difumina en HORIZONTAL y VERTICAL en vez de salir en columnas.
	float occ_mult = 1.0;   // 1 = niebla normal; 0 = bajo techo (cueva)
	if (occ.enabled) {
		vec3 orel = p - occ.center;
		float ou = dot(orel, occ.x_axis) * occ.inv_half;
		float ow = dot(orel, occ.z_axis) * occ.inv_half;
		if (abs(ou) <= 1.0 && abs(ow) <= 1.0) {   // fuera de la rejilla = sin dato = niebla normal
			vec2 ouv = vec2(ou, ow) * 0.5 + 0.5;
			float point_h = dot(orel, occ.up);
			float occ_accum = 0.0;
			for (int oy = -1; oy <= 1; oy++) {
				for (int ox = -1; ox <= 1; ox++) {
					vec2 suv = ouv + vec2(float(ox), float(oy)) * occ.step_uv;
					float ceil_h = texture(occ_height_tex, suv).r * occ.span - occ.below;
					// Aporte [0,1]: 1 bien bajo su techo (dentro), 0 al ras o por encima (fuera). Las
					// celdas "sin techo" decodifican muy abajo → su aporte es 0 (no ocluyen).
					occ_accum += clamp(((ceil_h + occ.margin) - point_h) * occ.inv_soft, 0.0, 1.0);
				}
			}
			occ_mult = 1.0 - occ_accum / 9.0;   // promedio 3x3 → borde difuso en todas direcciones
			if (occ_mult <= 0.001) {
				return 0.0;   // totalmente bajo techo: nos saltamos AMBOS FBM
			}
		}
	}

	float thickness = max(fog_max_r - fog_min_r, 0.001);
	float h = clamp((dist - fog_min_r) / thickness, 0.0, 1.0);

	// Densa en el suelo, se desvanece hacia el techo (curva suave para un borde superior difuso).
	float height_grad = 1.0 - smoothstep(0.0, 1.0, h);
	height_grad *= height_grad;
	if (height_grad <= 0.0001) {
		return 0.0;   // en el techo de la niebla no hay nada: evitamos AMBOS FBM.
	}

	// Banco de gran escala anclado al planeta y desplazado por el viento.
	float reference_r = max(fog_min_r, 1.0);
	vec3 noise_pos = (local / reference_r) * max(noise_scale, 0.001);
	noise_pos += wind_dir * wind_offset;

	float bank = _fbm(noise_pos, 3);
	// coverage alto → umbral bajo → más manto; coverage bajo → parches sueltos.
	float mass = smoothstep(1.0 - coverage, 1.0 - coverage + 0.28, bank);
	if (mass <= 0.0) {
		return 0.0;   // fuera del banco el detalle solo escalaría 0: nos saltamos su FBM.
	}

	// Jirones de detalle: ruido más fino que viaja algo más rápido, para que el banco respire.
	// 1 octava basta para el vaivén de los bordes; 2 apenas se distinguía y costaba el doble.
	float detail = _fbm(noise_pos * 4.3 + wind_dir * (wind_offset * 1.6), 1);
	mass *= mix(0.55, 1.0, detail);

	return height_grad * mass * occ_mult;
}

void march_fog(
	vec3 ro, vec3 rd, float max_dist,
	vec3 planet_center, float fog_min_r, float fog_max_r,
	float density, float coverage, float noise_scale,
	vec3 wind_dir, float wind_offset,
	vec3 sun_dir, float sun_intensity, vec3 fog_color,
	int steps, float jitter, float view_distance,
	out vec3 out_color, out float out_trans
) {
	out_color = vec3(0.0);
	out_trans = 1.0;

	vec2 outer = ray_sphere(planet_center, fog_max_r, ro, rd);
	if (outer.y <= 0.0) return;

	float t0 = outer.x;
	float t1 = outer.x + outer.y;

	// Recorte por la esfera interior (suelo de la niebla), igual que las nubes.
	vec2 inner = ray_sphere(planet_center, fog_min_r, ro, rd);
	if (inner.y > 0.0) {
		float ro_r = length(ro - planet_center);
		if (ro_r < fog_min_r) {
			t0 = max(t0, inner.x + inner.y);
		} else {
			t1 = min(t1, inner.x);
		}
	}

	t0 = max(t0, 0.0);
	t1 = min(t1, max_dist);
	// Distancia de visibilidad de la niebla: no marchamos más allá. Acota la niebla a un manto
	// local (la niebla a ras de suelo no se ve lejos), de modo que SIEMPRE cabe dentro de la
	// rejilla de oclusión → las cuevas se vacían sin tocar la resolución/tamaño de la rejilla.
	if (view_distance > 0.0) t1 = min(t1, view_distance);
	if (t1 <= t0 + 0.001) return;

	// El setup de la oclusión de cueva no depende del punto: se paga una vez por rayo.
	FogOcclusion occ = make_fog_occlusion();

	int fog_steps = clamp(steps, 1, 64);
	float step_size = (t1 - t0) / float(fog_steps);
	float t = t0 + step_size * jitter;

	for (int i = 0; i < fog_steps && t < t1; i++) {
		vec3 p = ro + rd * t;
		float d = sample_fog_density(p, planet_center, fog_min_r, fog_max_r,
		                             coverage, noise_scale, wind_dir, wind_offset, occ);
		// Desvanecido suave hacia la distancia de visibilidad para que no haya un corte duro al
		// llegar a view_distance (el banco se difumina en vez de terminar en una pared).
		if (view_distance > 0.0) {
			d *= 1.0 - smoothstep(view_distance * 0.6, view_distance, t);
		}
		if (d > 0.0001) {
			// Iluminación simple: ambiente + ganancia diurna + tinte cálido en el terminador.
			vec3 to_p = normalize(p - planet_center);
			float sun_dot = dot(to_p, sun_dir);
			// `day`: 0 en el lado nocturno, 1 en el diurno. Antes el suelo de ambiente (0.05)
			// NO estaba multiplicado por `day`, asi que con sun_intensity alto (20 por defecto)
			// la niebla quedaba igual de clara de noche -> no parecia afectada por el sol. Las
			// nubes en cambio multiplican TODO su lit por este factor. Lo replicamos aqui.
			float day = smoothstep(-0.15, 0.15, sun_dot);
			// Tinte de terminador CONDICIONAL al cielo despejado: lo escalamos por atmosphere_scatter
				// (P(23).w, ~1 en clear y ~0 en tormenta). Niebla de amanecer naranja, bruma de tormenta
				// gris (sol tapado por las nubes). La niebla es luz de sol pura: este gate es su "solo directa".
				float sunset_f = (1.0 - smoothstep(0.0, 0.3, abs(sun_dot))) * clamp(P(23).w, 0.0, 1.0);

			// El brillo se desvanece a 0 de noche, IGUAL que las nubes (que multiplican todo
			// su lit por day_night, sin suelo). Antes habia un suelo (0.02) que, x sun_intensity
			// (20), daba ~0.34 de base SIEMPRE; con ACES + bloom se veia como niebla BLANCA en
			// plena oscuridad. Sin suelo, la niebla nocturna se apaga como las nubes.
			float lit_amount = 0.16 * day;
			vec3 lit = fog_color * mix(vec3(1.0), vec3(3.0, 0.45, 0.05), sunset_f) * sun_intensity * lit_amount;

			float s_trans = exp(-d * step_size * density * 0.02);
			out_color += out_trans * (1.0 - s_trans) * lit;
			out_trans *= s_trans;

			if (out_trans < 0.01) { out_trans = 0.0; break; }
		}
		t += step_size;
	}
}


float density_at_point(
	vec3 p,
	vec3 planet_center,
	float planet_radius,
	float atmo_radius,
	float density_falloff
) {
	float h = length(p - planet_center) - planet_radius;
	float thickness = max(atmo_radius - planet_radius, 0.001);
	float h01 = clamp(h / thickness, 0.0, 1.0);
	return exp(-h01 * density_falloff) * (1.0 - h01);
}


float optical_depth(
	vec3 ro,
	vec3 rd,
	float ray_length,
	vec3 planet_center,
	float planet_radius,
	float atmo_radius,
	float density_falloff
) {
	vec3 p = ro;
	float step_size = ray_length / float(NUM_OPTICAL_DEPTH_POINTS - 1);
	float od = 0.0;
	for (int i = 0; i < NUM_OPTICAL_DEPTH_POINTS; i++) {
		od += density_at_point(p, planet_center, planet_radius, atmo_radius, density_falloff) * step_size;
		p += rd * step_size;
	}
	return od;
}


vec3 calculate_light(
	vec3 ro,
	vec3 rd,
	float ray_length,
	vec3 original_color,
	vec3 sun_dir,
	vec3 planet_center,
	float planet_radius,
	float atmo_radius,
	float density_falloff,
	vec3 scattering_coeffs,
	float sun_intensity,
	float view_from_space,
	float in_scatter_mult
) {
	vec3 in_scatter_point = ro;
	float step_size = ray_length / float(NUM_IN_SCATTER_POINTS - 1);
	vec3 in_scattered_light = vec3(0.0);

	// Optical depth de vista acumulado incrementalmente (regla del trapecio) con las mismas
	// muestras del bucle, en vez de re-marchar 12 puntos hacia atrás en cada iteración:
	// elimina la mitad de las evaluaciones de densidad del píxel sin diferencia visible.
	float view_ray_optical_depth = 0.0;
	float prev_density = 0.0;

	for (int i = 0; i < NUM_IN_SCATTER_POINTS; i++) {
		// Sombra suave angular: transición gradual alrededor del terminador.
		// sun_dot > 0 → día, sun_dot < 0 → noche; smoothstep da el gradiente.
		vec3 to_scatter = normalize(in_scatter_point - planet_center);
		float sun_dot = dot(to_scatter, sun_dir);
		float shadow_factor = smoothstep(-0.15, 0.15, sun_dot);

		float local_density = density_at_point(
			in_scatter_point, planet_center, planet_radius, atmo_radius, density_falloff
		);
		if (i > 0) {
			view_ray_optical_depth += 0.5 * (prev_density + local_density) * step_size;
		}
		prev_density = local_density;

		// Distancia desde el punto de muestra hasta salir de la atmósfera siguiendo al sol.
		float sun_ray_length = ray_sphere(planet_center, atmo_radius, in_scatter_point, sun_dir).y;
		float sun_ray_od = optical_depth(
			in_scatter_point, sun_dir, sun_ray_length,
			planet_center, planet_radius, atmo_radius, density_falloff
		);

		vec3 transmittance = exp(-(sun_ray_od + view_ray_optical_depth) * scattering_coeffs);

		// Tinte cálido en el terminador: rojo-naranja cuando sun_dot ≈ 0.
		float sunset_factor = 1.0 - smoothstep(0.0, 0.3, abs(sun_dot));
		vec3 sunset_tint = mix(vec3(1.0), vec3(3.0, 0.45, 0.05), sunset_factor);

		in_scattered_light += local_density * transmittance * scattering_coeffs * step_size * shadow_factor * sunset_tint;
		in_scatter_point += rd * step_size;
	}

	// in_scatter_mult < 1 atenúa el velo de Rayleigh bajo cielo encapotado (ver llamada): solo el
	// término aditivo, no los coeficientes, para no alterar la extinción de lo que hay detrás.
	in_scattered_light *= sun_intensity * in_scatter_mult;

	// Oscurecer la superficie del planeta en el lado nocturno (solo desde el espacio).
	vec3 lit_original = original_color;
	if (view_from_space > 0.5) {
		vec2 planet_hit = ray_sphere(planet_center, planet_radius + 400, ro, rd);
		if (planet_hit.y > 0.0) {
			vec3 surface_pt = ro + rd * planet_hit.x;
			float sn_dot = dot(normalize(surface_pt - planet_center), sun_dir);
			lit_original *= mix(0.05, 1.0, smoothstep(-0.15, 0.15, sn_dot));
		}
	}

	// Atenuación de lo que había detrás (terreno, objetos, cielo).
	vec3 original_color_transmittance = exp(-view_ray_optical_depth * scattering_coeffs);
	return lit_original * original_color_transmittance + in_scattered_light;
}


void main() {
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(P(0).xy);
	if (pixel.x >= size.x || pixel.y >= size.y) return;

	// Early-out sin tocar la imagen: el color buffer ya contiene la escena, así que
	// releerla y reescribirla solo quemaría ancho de banda.
	if (P(11).w < 0.5) return;

	vec2 uv = (vec2(pixel) + vec2(0.5)) / vec2(size);

	float planet_radius       = P(0).z;
	float atmo_radius         = P(0).w;
	float density_falloff     = P(5).w;
	float scattering_strength = P(6).w;
	float sun_intensity       = P(7).w;

	vec3 camera_position = P(8).xyz;          // (0,0,0): trabajamos relativo a cámara.
	vec3 planet_center   = P(9).xyz;
	vec3 sun_direction   = normalize(P(10).xyz);
	vec3 wavelengths     = P(11).rgb;         // nm (p.ej. 700, 530, 440)

	// Coeficientes de scattering tipo Rayleigh: (400/λ)^4 * strength.
	vec3 scattering_coefficients = vec3(
		pow(400.0 / max(wavelengths.r, 1.0), 4.0),
		pow(400.0 / max(wavelengths.g, 1.0), 4.0),
		pow(400.0 / max(wavelengths.b, 1.0), 4.0)
	) * scattering_strength;

	// Dirección del rayo en mundo.
	vec3 view_probe = reconstruct_view_position(uv, 0.0001);
	vec3 ray_dir = normalize(view_to_world_dir(view_probe));

	// Profundidad de escena (Godot reverse-Z: cerca ~1, lejos/cielo ~0).
	float depth_sample = texelFetch(depth_texture, pixel, 0).r;
	bool has_scene_depth = depth_sample > 1e-7;
	float scene_t = MAX_FLOAT;
	if (has_scene_depth) {
		vec3 scene_view_position = reconstruct_view_position(uv, depth_sample);
		scene_t = length(scene_view_position);
	}

	// Intersección con la atmósfera.
	vec2 atmo = ray_sphere(planet_center, atmo_radius, camera_position, ray_dir);
	float dst_to_atmo      = atmo.x;
	float dst_through_atmo = atmo.y;

	// Limita el recorrido por el terreno/objetos (clave para que se vea atmósfera sobre el suelo).
	dst_through_atmo = min(dst_through_atmo, max(scene_t - dst_to_atmo, 0.0));

	if (dst_through_atmo <= 0.0) return;

	// El color de escena solo se lee cuando de verdad vamos a componer algo encima.
	vec4 scene_color = imageLoad(color_image, pixel);

	vec3 entry_point = camera_position + ray_dir * (dst_to_atmo + EPSILON);

	float view_from_space = dst_to_atmo > EPSILON ? 1.0 : 0.0;

	// Sombra de las nubes proyectada sobre el terreno visible. Se aplica al color de
	// escena ANTES de la atmósfera, para que el in-scatter se calcule sobre la
	// superficie ya oscurecida. Reutiliza la misma densidad que dibuja las nubes,
	// así la sombra coincide exactamente con lo que se ve arriba.
	float cloud_shadow_strength = P(8).w;
	if (has_scene_depth && P(13).w > 0.5 && cloud_shadow_strength > 0.0) {
		float sh_cloud_min_r = planet_radius + P(12).x;
		float sh_cloud_max_r = planet_radius + P(12).y;
		vec3 surface_p = camera_position + ray_dir * scene_t;
		if (length(surface_p - planet_center) < sh_cloud_max_r) {
			float sh_jitter = _hash3f(vec3(float(pixel.x), float(pixel.y), 7.0)) - 0.5;
			float trans = cloud_shadow_transmittance(
				surface_p, sun_direction, planet_center,
				sh_cloud_min_r, sh_cloud_max_r,
				P(12).w, P(12).z, P(13).z, P(13).x,
				sh_jitter
			);
			// Solo lado diurno; fundido suave alrededor del terminador.
			float day = smoothstep(-0.05, 0.1,
				dot(normalize(surface_p - planet_center), sun_direction));
			scene_color.rgb *= mix(1.0, trans, cloud_shadow_strength * day);
		}
	}

	// Multiplicador del in-scatter de Rayleigh (velo azul de perspectiva aérea), parámetro propio del
	// clima (P(23).w, atmosphere_scatter): 1 = dispersión plena, 0 = horizonte plomizo sin azul. Se
	// fija por evento en weather_events.json, desligado de cloud_shadow.
	float in_scatter_mult = clamp(P(23).w, 0.0, 1.0);

	// Nubes volumétricas — se aplican antes del scattering atmosférico.
	// 1. Primero calcula la atmósfera sobre la escena original.
	vec3 light = calculate_light(
		entry_point,
		ray_dir,
		max(dst_through_atmo - EPSILON * 2.0, 0.0),
		scene_color.rgb,
		sun_direction,
		planet_center,
		planet_radius,
		atmo_radius,
		density_falloff,
		scattering_coefficients,
		sun_intensity,
		view_from_space,
		in_scatter_mult
	);

	// 2. Después compón las nubes delante de la atmósfera.
	if (P(13).w > 0.5) {
		float cloud_min_r = planet_radius + P(12).x;
		float cloud_max_r = planet_radius + P(12).y;

		vec3  cloud_col;
		float cloud_trans;

		float cloud_max_dist = min(scene_t, dst_to_atmo + dst_through_atmo);

		// Jitter por píxel: desplaza el origen del march de forma distinta en cada píxel
		// para que los artefactos de escalón no sean coherentes al mover la cámara.
		float cloud_jitter = _hash3f(vec3(float(pixel.x), float(pixel.y), 0.0));

		march_clouds(
			camera_position, ray_dir, cloud_max_dist,
			planet_center, cloud_min_r, cloud_max_r,
			P(12).z, P(12).w,
			P(13).x, P(13).y, P(13).z,
			sun_direction, sun_intensity, planet_radius,
			cloud_jitter,
			cloud_col, cloud_trans
		);

		light = light * cloud_trans + cloud_col;
	}

	// 3. Niebla a ras de suelo — lo más cercano, se compone delante de todo. Su banco
	//    viaja con el viento, así se ve llegar de lejos en vez de bajar las nubes.
	if (P(17).w > 0.5 && P(16).z > 0.001) {
		float fog_min_r = planet_radius + P(16).x;
		float fog_max_r = planet_radius + P(16).y;

		vec3  fog_col;
		float fog_trans;

		float fog_max_dist = min(scene_t, dst_to_atmo + dst_through_atmo);
		float fog_jitter = _hash3f(vec3(float(pixel.x), float(pixel.y), 3.0));

		march_fog(
			camera_position, ray_dir, fog_max_dist,
			planet_center, fog_min_r, fog_max_r,
			P(16).z, P(16).w, P(18).x,
			P(14).xyz, P(18).y,
			sun_direction, sun_intensity, P(17).rgb,
			int(P(18).z), fog_jitter, P(18).w,
			fog_col, fog_trans
		);

		light = light * fog_trans + fog_col;
	}

	imageStore(color_image, pixel, vec4(light, scene_color.a));
}