shader_type spatial;
// Roca del planeta (scripts/planet/procedural_rock.gd): las rocas grandes, las piedras sueltas y los
// afloramientos de mena.
//
// - Textura triplanar en los ejes de la roca y en metros (con la escala de la instancia): no estira
//   como el UV esférico de antes, cada roca lleva su dibujo pegado y la densidad es la del terreno.
// - Albedo calibrado como el del terreno (texture_albedo / slope_albedo del JSON). La roca de las
//   laderas es bumpy_worn_ground × 0,55; con la misma textura y el mismo factor, las rocas se leen
//   como la misma piedra en vez de como manchas claras.
// - Sin translucencia ni rim: eran del follaje y aclaraban la roca a contraluz y en el contorno.
// - Oclusión de las cavidades (COLOR.r, del generador) y del mapa empaquetado (G).
// - Tierra en el contacto con el suelo y musgo en lo que mira arriba, solo en la cara curtida
//   (COLOR.g): las caras que deja un corte al picarla salen limpias.
// - Envejecido: manchas grandes de tono (una roca no es de un color parejo) y chorreones del agua en
//   las caras de lado.
// - Nieve del clima frío, como opaque_planet_material.

render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/lib/planet_lighting.gdshaderinc"
#include "res://shaders/lib/climate.gdshaderinc"

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

group_uniforms stone;
uniform sampler2D texture_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D texture_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// Mapa empaquetado del terreno (material_rah.png): R = rugosidad, G = oclusión, B = altura.
uniform sampler2D texture_rah : hint_default_white, filter_linear_mipmap, repeat_enable;
// Rugosidad suelta (R), para las texturas que no traen el mapa empaquetado. Se multiplica.
uniform sampler2D texture_roughness : hint_default_white, filter_linear_mipmap, repeat_enable;
// Repeticiones por metro: 0,5 = una cada 2 m, como el terreno (texture_scale).
uniform float texture_scale = 0.5;
// Calibración, como la del terreno: multiplicador lineal, tinte lineal y saturación.
uniform float albedo_gain = 0.55;
uniform vec3 albedo_tint = vec3(1.05, 1.0, 0.92);
uniform float albedo_saturation : hint_range(0.0, 2.0) = 1.0;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float roughness_scale : hint_range(0.0, 1.5) = 1.0;
// Variación de brillo de una roca a otra (±). Sale de la escala de la instancia, que el instancer
// sortea y que los trozos de una roca picada conservan.
uniform float variation : hint_range(0.0, 0.5) = 0.12;
uniform float cavity_strength : hint_range(0.0, 1.0) = 1.0;
uniform float texture_ao_strength : hint_range(0.0, 1.0) = 0.8;
// Parte de la oclusión que oscurece también la luz directa (el terreno usa 0,35).
uniform float direct_ao : hint_range(0.0, 1.0) = 0.35;

group_uniforms weathering;
// Manchas grandes de brillo y de tono (más cálido / más frío), de macro_size metros.
uniform float macro_variation : hint_range(0.0, 0.5) = 0.15;
uniform float macro_size = 1.2;
// Chorreones verticales en las caras de lado: cuánto oscurecen y su ancho en metros.
uniform float streak_strength : hint_range(0.0, 0.6) = 0.2;
uniform float streak_size = 0.25;

group_uniforms ground;
// Tierra pegada al pie de la roca, hasta base_height metros sobre el suelo (y = 0 de la malla).
uniform vec3 base_color : source_color = vec3(0.3, 0.26, 0.21);
uniform float base_height = 0.35;
uniform float base_strength : hint_range(0.0, 1.0) = 0.6;

group_uniforms moss;
// Musgo en lo que mira arriba (en los ejes de la roca, así que los trozos que caen lo conservan).
uniform float moss_amount : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D moss_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// El de la pradera del terreno (texture_albedo del JSON), para que el musgo case con la hierba.
uniform float moss_gain = 1.4;
uniform vec3 moss_tint = vec3(1.0);
// N·arriba desde el que crece y lo suave del borde.
uniform float moss_threshold : hint_range(-1.0, 1.0) = 0.45;
uniform float moss_softness : hint_range(0.01, 1.0) = 0.25;
uniform float moss_scale = 0.7;
group_uniforms;

// Nieve del clima frío (climate.gdshaderinc): 0 = nunca, 1 = la del sitio.
uniform float climate_snow_amount : hint_range(0.0, 1.0) = 1.0;

// Dónde queda la malla de un trozo dentro de la roca entera (RockFracture la recentra en su centroide):
// con él, los trozos siguen con su textura, su tierra y su musgo en el mismo sitio.
instance uniform vec3 rock_offset;

// Posición en metros y en los ejes de la roca, desde su base.
varying vec3 v_rock_pos;
varying vec3 v_rock_normal;
varying flat float v_variation;
varying float v_snow_cover;
varying float v_glacier;

void vertex() {
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	v_rock_pos = (VERTEX + rock_offset) * scale;
	v_rock_normal = NORMAL;
	v_variation = fract(sin(dot(scale, vec3(12.9898, 78.233, 37.719))) * 43758.5453);

	vertex_position_global = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	planet_normal = normalize(vertex_position_global - planet_position);

	v_snow_cover = 0.0;
	v_glacier = 0.0;
	if (climate_snow_amount > 0.0) {
		float cold = climate_snow_coldness(vertex_position_global - planet_position);
		v_snow_cover = climate_snow_cover(cold) * climate_snow_amount;
		v_glacier = climate_glacier(cold) * climate_snow_amount;
	}
}

void fragment() {
	vec3 n_geo = normalize(v_rock_normal);
	vec3 w = pow(abs(n_geo), vec3(4.0));
	w /= w.x + w.y + w.z;
	// Cada proyección con su orientación (y su espejo en la cara opuesta), para que el normal map
	// empuje hacia el lado bueno: X: u = -z, v = -y. Y: u = x, v = z. Z: u = x, v = -y.
	vec3 s = vec3(n_geo.x < 0.0 ? -1.0 : 1.0, n_geo.y < 0.0 ? -1.0 : 1.0, n_geo.z < 0.0 ? -1.0 : 1.0);
	vec3 p = v_rock_pos * texture_scale;
	vec2 uv_x = vec2(-p.z * s.x, -p.y);
	vec2 uv_y = vec2(p.x * s.y, p.z);
	vec2 uv_z = vec2(p.x * s.z, -p.y);

	vec3 color = texture(texture_albedo, uv_x).rgb * w.x + texture(texture_albedo, uv_y).rgb * w.y
		+ texture(texture_albedo, uv_z).rgb * w.z;
	color = mix(vec3(dot(color, LUMA)), color, albedo_saturation) * albedo_tint * albedo_gain;
	color *= 1.0 + (v_variation - 0.5) * 2.0 * variation;

	vec3 rah = texture(texture_rah, uv_x).rgb * w.x + texture(texture_rah, uv_y).rgb * w.y
		+ texture(texture_rah, uv_z).rgb * w.z;
	float rough = rah.r * roughness_scale * (texture(texture_roughness, uv_x).r * w.x
		+ texture(texture_roughness, uv_y).r * w.y + texture(texture_roughness, uv_z).r * w.z);

	// Normal map triplanar (whiteout), en los ejes de la roca.
	vec3 tx = texture(texture_normal, uv_x).rgb * 2.0 - 1.0;
	vec3 ty = texture(texture_normal, uv_y).rgb * 2.0 - 1.0;
	vec3 tz = texture(texture_normal, uv_z).rgb * 2.0 - 1.0;
	tx.xy *= normal_strength;
	ty.xy *= normal_strength;
	tz.xy *= normal_strength;
	vec3 nx = vec3(abs(tx.z) * n_geo.x, tx.y + n_geo.y, -s.x * tx.x + n_geo.z);
	vec3 ny = vec3(s.y * ty.x + n_geo.x, abs(ty.z) * n_geo.y, -ty.y + n_geo.z);
	vec3 nz = vec3(s.z * tz.x + n_geo.x, tz.y + n_geo.y, abs(tz.z) * n_geo.z);
	vec3 n_rock = normalize(nx * w.x + ny * w.y + nz * w.z);

	float weathered = COLOR.g;
	// Manchas grandes de tono, y chorreones del agua por los lados de la cara curtida.
	float macro = climate_value_noise(v_rock_pos / macro_size) * 0.7
		+ climate_value_noise(v_rock_pos / (macro_size * 0.4)) * 0.3;
	color *= (1.0 + (macro - 0.5) * 2.0 * macro_variation) * mix(vec3(1.03, 1.0, 0.95), vec3(0.97, 1.0, 1.04), macro);
	vec3 run = v_rock_pos * vec3(1.0, 0.12, 1.0) / streak_size;
	float streak = smoothstep(0.5, 0.85, climate_value_noise(run) * 0.7 + climate_value_noise(run * 2.7) * 0.3);
	streak *= (1.0 - smoothstep(0.3, 0.8, abs(n_geo.y))) * weathered;
	color *= 1.0 - streak * streak_strength;
	// Tierra al pie: sube más por los huecos del relieve que por los salientes.
	float dirt = 1.0 - smoothstep(0.0, base_height, v_rock_pos.y + (rah.b - 0.5) * base_height * 0.8);
	dirt *= base_strength * weathered;
	color = mix(color, base_color, dirt);

	// Musgo: en lo que mira arriba, a manchas, y antes en los huecos que en los salientes.
	if (moss_amount > 0.0) {
		float patches = climate_value_noise(v_rock_pos * 0.9) * 0.65 + climate_value_noise(v_rock_pos * 3.1) * 0.35;
		float facing = n_rock.y + (patches - 0.5) * 0.7 + (0.5 - rah.b) * 0.4;
		float moss = smoothstep(moss_threshold - moss_softness, moss_threshold + moss_softness, facing);
		moss *= moss_amount * weathered * (1.0 - dirt);
		vec3 moss_color = texture(moss_texture, v_rock_pos.xz * moss_scale).rgb * moss_gain * moss_tint;
		color = mix(color, moss_color, moss);
		rough = mix(rough, 0.95, moss);
		n_rock = normalize(mix(n_rock, n_geo, moss * 0.6));
	}

	float ao = mix(1.0, rah.g, texture_ao_strength) * mix(1.0, COLOR.r, cavity_strength) * (1.0 - dirt * 0.4);

	ALBEDO = color;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	METALLIC = 0.0;
	// Sin especular: el light() planetario no lo calcula y el juego no tiene reflejos, y con
	// SPECULAR > 0 la cara al sol sale quemada a blanco (lo mismo les pasa a los materiales de
	// opaque_planet_material con specular > 0; visto en tests/world/rock_review).
	SPECULAR = 0.0;
	AO = ao;
	AO_LIGHT_AFFECT = direct_ao;
	NORMAL = normalize(mat3(VIEW_MATRIX) * (MODEL_NORMAL_MATRIX * n_rock));

	// Nieve y escarcha, con la normal de la malla en el mundo (la que decide qué mira al cielo).
	if (v_snow_cover > 0.001 || v_glacier > 0.001) {
		vec3 world_normal = normalize(MODEL_NORMAL_MATRIX * n_geo);
		vec3 local = vertex_position_global - planet_position;
		float snow = climate_object_snow(v_snow_cover, v_glacier, dot(world_normal, planet_normal), local);
		float rime = v_glacier * (1.0 - snow) * 0.45;
		ALBEDO = mix(ALBEDO, CLIMATE_RIME_ALBEDO, rime);
		ROUGHNESS = mix(ROUGHNESS, 0.35, rime);
		ALBEDO = mix(ALBEDO, CLIMATE_SNOW_ALBEDO, snow);
		ROUGHNESS = mix(ROUGHNESS, 0.85, snow);
		NORMAL = normalize(mix(NORMAL, mat3(VIEW_MATRIX) * (MODEL_NORMAL_MATRIX * n_geo), snow * 0.8));
		AO = mix(AO, 1.0, snow * 0.5);
	}
}

void light() {
	vec3 up_view = normalize((VIEW_MATRIX * vec4(planet_normal, 0.0)).xyz);
	vec3 d, s;
	// detail = 0: sin translucencia ni rim.
	compute_planet_light(
		NORMAL, VIEW, LIGHT, LIGHT_COLOR, ATTENUATION,
		ALBEDO, METALLIC, ROUGHNESS, 0.0,
		up_view, LIGHT_IS_DIRECTIONAL, 0.0, d, s);
	DIFFUSE_LIGHT += d;
	SPECULAR_LIGHT += s;
}
